#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    if (-not (Initialize-TestDataIfMissing)) {
        throw "Cannot run tests: Test data initialization failed. Please ensure SOPS and age are installed."
    }

    Remove-OrphanedTestVaults

    $script:testState = Initialize-TestEnvironment

    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    if (-not (Get-Module Microsoft.PowerShell.SecretManagement -ListAvailable)) {
        throw "Microsoft.PowerShell.SecretManagement module is required. Install with: Install-Module Microsoft.PowerShell.SecretManagement"
    }
    Import-Module Microsoft.PowerShell.SecretManagement -Force

    # Configure test-specific age key
    $testDataPath = Join-Path $PSScriptRoot 'TestData'
    $testKeyFile = Join-Path $testDataPath 'test-key.txt'
    if (-not (Test-Path $testKeyFile)) {
        throw "Test key file not found: $testKeyFile"
    }

    $env:SOPS_AGE_KEY_FILE = $testKeyFile

    $publicKeyLine = Get-Content $testKeyFile | Select-Object -Skip 1 -First 1
    if ($publicKeyLine -match 'public key:\s*(.+)') {
        $script:TestAgePublicKey = $matches[1].Trim()
    }
    else {
        throw "Failed to extract public key from $testKeyFile"
    }

    # Create test vault with nested structure
    $script:TestSecretsPath = Join-Path $TestDrive 'secrets'

    foreach ($dir in @('apps\foo\bar\dv1', 'apps\baz\prod', 'database', 'k8s')) {
        $null = New-Item -Path (Join-Path $script:TestSecretsPath $dir) -ItemType Directory -Force
    }

    # Create .sops.yaml config
    @"
creation_rules:
  - path_regex: \.yaml$
    age: $script:TestAgePublicKey
"@ | Set-Content (Join-Path $script:TestSecretsPath '.sops.yaml')

    # Create and encrypt test secret files
    $testSecrets = @{
        'apps\foo\bar\dv1\secret.yaml' = @'
key: value
password: secret123
'@
        'apps\foo\bar\dv1\config.yaml' = @'
setting: true
'@
        'apps\baz\prod\secret.yaml'    = @'
key: different-value
'@
        'database\postgres.yaml'       = @'
username: dbuser
password: dbpass
'@
        'api-key.yaml'                 = @'
apikey: rootlevelkey
'@
        'k8s\myapp.yaml'               = @'
apiVersion: v1
kind: Secret
metadata:
  name: software-license
  namespace: myapp
type: Opaque
stringData:
  license-key: ABC-123-XYZ
  config: |
    cluster.name=test
'@
    }

    foreach ($file in $testSecrets.Keys) {
        $filePath = Join-Path $script:TestSecretsPath $file
        $testSecrets[$file] | Set-Content $filePath -NoNewline

        Push-Location $script:TestSecretsPath
        try {
            $encrypted = & sops --encrypt --in-place $filePath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to encrypt $file : $encrypted"
            }
        }
        finally {
            Pop-Location
        }
    }

    # Register vault with RelativePath naming strategy
    $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsNamespaceTest' -ModulePath $modulePath -VaultParameters @{
        Path           = $script:TestSecretsPath
        FilePattern    = '*.yaml'
        Recurse        = $true
        NamingStrategy = 'RelativePath'
    }
}

AfterAll {
    if ($script:TestVaultName) {
        Remove-IsolatedTestVault -VaultName $script:TestVaultName
    }

    Restore-TestEnvironment -State $script:testState
}

Describe 'Namespace Extraction' -Tag 'Namespace', 'Unit' {
    Context 'Index Structure' {
        It 'Should extract namespace from deeply nested path' {
            $index = Get-SecretIndex -Path $script:TestSecretsPath -FilePattern '*.yaml' -Recurse $true `
                -NamingStrategy 'RelativePath'

            $deepEntry = $index | Where-Object { $_.Name -eq 'apps/foo/bar/dv1/secret' }

            $deepEntry | Should -Not -BeNullOrEmpty
            $deepEntry.Namespace | Should -Be 'apps/foo/bar/dv1'
            $deepEntry.ShortName | Should -Be 'secret'
            $deepEntry.Name | Should -Be 'apps/foo/bar/dv1/secret'
        }

        It 'Should extract namespace from single-level path' {
            $index = Get-SecretIndex -Path $script:TestSecretsPath -FilePattern '*.yaml' -Recurse $true `
                -NamingStrategy 'RelativePath'

            $dbEntry = $index | Where-Object { $_.Name -eq 'database/postgres' }

            $dbEntry | Should -Not -BeNullOrEmpty
            $dbEntry.Namespace | Should -Be 'database'
            $dbEntry.ShortName | Should -Be 'postgres'
            $dbEntry.Name | Should -Be 'database/postgres'
        }

        It 'Should handle vault root files with empty namespace' {
            $index = Get-SecretIndex -Path $script:TestSecretsPath -FilePattern '*.yaml' -Recurse $true `
                -NamingStrategy 'RelativePath'

            $rootEntry = $index | Where-Object { $_.ShortName -eq 'api-key' -and $_.Namespace -eq '' }

            $rootEntry | Should -Not -BeNullOrEmpty
            $rootEntry.Namespace | Should -Be ''
            $rootEntry.ShortName | Should -Be 'api-key'
            $rootEntry.Name | Should -Be 'api-key'
        }
    }
}

Describe 'Full Path Resolution' -Tag 'Namespace', 'Integration' {
    Context 'Exact Path Matching' {
        It 'Should retrieve secret with full path' {
            $secret = Get-Secret -Name 'database/postgres' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'username:\s*dbuser'
        }

        It 'Should retrieve deeply nested secret with full path' {
            $secret = Get-Secret -Name 'apps/foo/bar/dv1/secret' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'key:\s*value'
        }

        It 'Should return null for non-existent path' {
            $secret = Get-Secret -Name 'does/not/exist' -Vault $script:TestVaultName -AsPlainText -ErrorAction SilentlyContinue

            $secret | Should -BeNullOrEmpty
        }
    }
}

Describe 'Kubernetes Secret Handling' -Tag 'Namespace', 'K8s', 'Integration' {
    Context 'Full K8s Secret (Raw YAML)' {
        It 'Should return raw YAML string' {
            $secret = Get-Secret -Name 'k8s/myapp' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'apiVersion:\s*v1'
            $secret | Should -Match 'kind:\s*Secret'
            $secret | Should -Match 'stringData:'
        }
    }
}

Describe 'Short Name Resolution and Collision Detection' -Tag 'Namespace', 'Collision', 'Integration' {
    Context 'Unique Short Name (Backward Compatibility)' {
        It 'Should retrieve secret by unique short name' {
            $secret = Get-Secret -Name 'postgres' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'username:\s*dbuser'
        }

        It 'Should retrieve secret with unique short name api-key' {
            $secret = Get-Secret -Name 'api-key' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'apikey:\s*rootlevelkey'
        }
    }

    Context 'Collision Detection' {
        It 'Should throw error when short name is ambiguous' {
            # Both apps/foo/bar/dv1/secret and apps/baz/prod/secret exist
            try {
                Get-Secret -Name 'secret' -Vault $script:TestVaultName -ErrorAction Stop
                throw "Should have thrown error"
            }
            catch {
                $errorMsg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                $errorMsg | Should -Match 'Multiple secrets'
            }
        }

        It 'Error message should list all matching full paths' {
            try {
                Get-Secret -Name 'secret' -Vault $script:TestVaultName -ErrorAction Stop
                throw "Should have thrown error"
            }
            catch {
                $errorMsg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                $errorMsg | Should -Match 'apps/foo/bar/dv1/secret'
                $errorMsg | Should -Match 'apps/baz/prod/secret'
            }
        }

        It 'Error message should suggest using full path' {
            try {
                Get-Secret -Name 'secret' -Vault $script:TestVaultName -ErrorAction Stop
                throw "Should have thrown error"
            }
            catch {
                $errorMsg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                $errorMsg | Should -Match 'specify the full path'
                $errorMsg | Should -Match 'Get-Secret'
            }
        }
    }
}

Describe 'Get-SecretInfo Metadata' -Tag 'Namespace', 'Metadata', 'Integration' {
    Context 'Namespace Metadata' {
        It 'Should include Namespace in metadata' {
            $info = Get-SecretInfo -Name 'database/postgres' -Vault $script:TestVaultName

            $info | Should -Not -BeNullOrEmpty
            $info.Metadata | Should -Not -BeNullOrEmpty
            $info.Metadata.Namespace | Should -Be 'database'
        }

        It 'Should include ShortName in metadata' {
            $info = Get-SecretInfo -Name 'database/postgres' -Vault $script:TestVaultName
            $info.Metadata.ShortName | Should -Be 'postgres'
        }

        It 'Should display full path as Name' {
            $info = Get-SecretInfo -Name 'apps/foo/bar/dv1/secret' -Vault $script:TestVaultName
            $info.Name | Should -Be 'apps/foo/bar/dv1/secret'
        }

        It 'Should handle empty namespace for root files' {
            $info = Get-SecretInfo -Name 'api-key' -Vault $script:TestVaultName

            $info.Metadata.Namespace | Should -Be ''
            $info.Metadata.ShortName | Should -Be 'api-key'
        }
    }

    Context 'Wildcard Filters' {
        It 'Should support wildcard filter for namespace' {
            $infos = Get-SecretInfo -Name 'apps/foo/*' -Vault $script:TestVaultName

            $infos | Should -Not -BeNullOrEmpty
            $infos.Count | Should -BeGreaterThan 0

            $names = $infos.Name
            $names | Should -Contain 'apps/foo/bar/dv1/secret'
            $names | Should -Contain 'apps/foo/bar/dv1/config'
        }

        It 'Should filter by top-level namespace' {
            $infos = Get-SecretInfo -Name 'database/*' -Vault $script:TestVaultName

            $infos | Should -Not -BeNullOrEmpty
            $infos.Name | Should -Contain 'database/postgres'
        }

        It 'Should support wildcard for all secrets' {
            $infos = Get-SecretInfo -Name '*' -Vault $script:TestVaultName

            $infos | Should -Not -BeNullOrEmpty
            $infos.Count | Should -BeGreaterOrEqual 6
        }
    }
}

Describe 'Backward Compatibility' -Tag 'Namespace', 'Compatibility', 'Integration' {
    Context 'Existing Functionality' {
        It 'Should work with existing RelativePath full names' {
            $secret = Get-Secret -Name 'database/postgres' -Vault $script:TestVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'password:\s*dbpass'
        }

        It 'Should work with unique short names without regression' {
            $secret = Get-Secret -Name 'postgres' -Vault $script:TestVaultName -AsPlainText
            $secret | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Edge Cases' -Tag 'Namespace', 'EdgeCases', 'Integration' {
    BeforeAll {
        $script:EdgeCaseVaultName = 'SopsEdgeCaseVault'
        $script:EdgeCaseSecretsPath = Join-Path $PSScriptRoot 'TestData'

        Unregister-SecretVault -Name $script:EdgeCaseVaultName -ErrorAction SilentlyContinue

        Register-SecretVault -Name $script:EdgeCaseVaultName -ModuleName $modulePath -VaultParameters @{
            Path           = $script:EdgeCaseSecretsPath
            FilePattern    = '*.yaml'
            Recurse        = $true
            NamingStrategy = 'RelativePath'
        }
    }

    AfterAll {
        if ($script:EdgeCaseVaultName) {
            Unregister-SecretVault -Name $script:EdgeCaseVaultName -ErrorAction SilentlyContinue
        }
    }

    Context 'Deep Nesting' {
        It 'Should handle 6 levels of nesting' {
            $secret = Get-Secret -Name 'a/b/c/d/e/f/deep-secret' -Vault $script:EdgeCaseVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'value:\s*deeply-nested'
        }

        It 'Should extract correct namespace from deep path' {
            $info = Get-SecretInfo -Name 'a/b/c/d/e/f/deep-secret' -Vault $script:EdgeCaseVaultName

            $info.Metadata.Namespace | Should -Be 'a/b/c/d/e/f'
            $info.Metadata.ShortName | Should -Be 'deep-secret'
        }
    }

    Context 'Special Characters' {
        It 'Should handle hyphens in namespace' {
            $secret = Get-Secret -Name 'env-prod/api_key-v2' -Vault $script:EdgeCaseVaultName -AsPlainText

            $secret | Should -Not -BeNullOrEmpty
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'key:\s*special-chars'
        }

        It 'Should handle underscores in short name' {
            $info = Get-SecretInfo -Name 'env-prod/api_key-v2' -Vault $script:EdgeCaseVaultName
            $info.Metadata.ShortName | Should -Be 'api_key-v2'
        }
    }

    Context 'Empty Vault' {
        It 'Should handle empty vault gracefully' {
            $emptyVaultName = 'SopsEmptyVault'
            $emptyPath = Join-Path $TestDrive 'empty'
            $null = New-Item -Path $emptyPath -ItemType Directory -Force

            Unregister-SecretVault -Name $emptyVaultName -ErrorAction SilentlyContinue

            Register-SecretVault -Name $emptyVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $emptyPath
                FilePattern = '*.yaml'
                Recurse     = $true
            }

            $infos = Get-SecretInfo -Vault $emptyVaultName
            $infos | Should -BeNullOrEmpty

            Unregister-SecretVault -Name $emptyVaultName -ErrorAction SilentlyContinue
        }
    }
}
