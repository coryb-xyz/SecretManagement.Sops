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

    $testDataPath = Join-Path $PSScriptRoot 'TestData'
    $testKeyFile = Join-Path $testDataPath 'test-key.txt'
    if (-not (Test-Path $testKeyFile)) {
        throw "Test key file not found: $testKeyFile"
    }
    $env:SOPS_AGE_KEY_FILE = $testKeyFile

    # Extract public key once for reuse across vault registrations
    $ageKeyContent = Get-Content $testKeyFile -Raw
    if ($ageKeyContent -match 'public key: (.+)') {
        $script:AgePublicKey = $Matches[1].Trim()
    }

    # Helper: creates a .sops.yaml config in the given directory
    function script:New-SopsConfig {
        param(
            [string]$Path,
            [string]$EncryptedRegex
        )
        $lines = @(
            'creation_rules:'
            '  - path_regex: \.yaml$'
        )
        if ($EncryptedRegex) {
            $lines += "    encrypted_regex: $EncryptedRegex"
        }
        $lines += "    age: $script:AgePublicKey"
        Set-Content -Path (Join-Path $Path '.sops.yaml') -Value ($lines -join "`n")
    }
}

AfterAll {
    Restore-TestEnvironment -State $script:testState
}

Describe 'Set-Secret' -Tag 'WriteSupport', 'Integration' {
    BeforeAll {
        $script:TestSecretsPath = Join-Path $TestDrive 'secrets'
        $null = New-Item -Path $script:TestSecretsPath -ItemType Directory -Force

        New-SopsConfig -Path $script:TestSecretsPath

        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsWriteTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
            Recurse     = $false
        }
    }

    AfterAll {
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'Secret Type Support' -Tag 'SecretTypes' {
        BeforeEach {
            $script:TestSecretName = "test-$(New-Guid)"
        }

        AfterEach {
            if ($script:TestSecretName) {
                try {
                    $secretExists = Get-SecretInfo -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction Stop
                    if ($secretExists) {
                        Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction Stop
                    }
                }
                catch [Microsoft.PowerShell.SecretManagement.SecretNotFoundException] {
                    Write-Verbose "Secret '$script:TestSecretName' not found during cleanup (expected)"
                }
                catch {
                    Write-Warning "Failed to clean up secret '$script:TestSecretName': $_"
                }
            }
        }

        It 'Supports String secret type' {
            $testValue = 'plain-text-secret-value'

            Set-Secret -Name $script:TestSecretName -Secret $testValue -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                'value' = $testValue
            } | Should -Be $true
        }

        It 'Supports SecureString secret type' {
            $testValue = ConvertTo-SecureString 'secure-password-123' -AsPlainText -Force

            Set-Secret -Name $script:TestSecretName -Secret $testValue -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                'value' = 'secure-password-123'
            } | Should -Be $true
        }

        It 'Supports PSCredential secret type' {
            $testCred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'testpass123' -AsPlainText -Force))

            Set-Secret -Name $script:TestSecretName -Secret $testCred -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                'username' = 'testuser'
                'password' = 'testpass123'
            } | Should -Be $true
        }

        It 'Supports Hashtable secret type' {
            $testHash = @{
                database_host = 'postgres.example.com'
                database_port = 5432
                database_name = 'production'
                ssl_enabled   = $true
            }

            Set-Secret -Name $script:TestSecretName -Secret $testHash -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                database_host = 'postgres.example.com'
                database_port = 5432
                database_name = 'production'
                ssl_enabled   = $true
            } | Should -Be $true
        }

        It 'Supports byte array secret type' {
            $testBytes = [System.Text.Encoding]::UTF8.GetBytes('binary-content-data')

            Set-Secret -Name $script:TestSecretName -Secret $testBytes -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:'
        }
    }

    Context 'File Creation and Management' -Tag 'FileOperations' {
        BeforeEach {
            $script:TestSecretName = "test-$(New-Guid)"
        }

        AfterEach {
            if ($script:TestSecretName -and (Get-SecretInfo -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue)) {
                Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Creates new YAML file for new secret' {
            Set-Secret -Name $script:TestSecretName -Secret 'test-value' -Vault $script:TestVaultName

            $expectedFile = Join-Path $script:TestSecretsPath "$($script:TestSecretName).yaml"
            $expectedFile | Should -Exist
        }

        It 'Encrypts file with SOPS' {
            Set-Secret -Name $script:TestSecretName -Secret 'sensitive-data' -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestSecretsPath "$($script:TestSecretName).yaml"
            $content = Get-Content $filePath -Raw

            $content | Should -Match 'sops:'
            $content | Should -Match 'version:'
            $content | Should -Match 'ENC\['
        }

        It 'Creates directory structure if missing' {
            $nestedPath = Join-Path $script:TestSecretsPath 'nested\deep\path'
            $null = New-Item -Path $nestedPath -ItemType Directory -Force

            New-SopsConfig -Path $nestedPath

            Unregister-SecretVault -Name $script:TestVaultName
            Register-SecretVault -Name $script:TestVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $nestedPath
                FilePattern = '*.yaml'
            }

            Set-Secret -Name $script:TestSecretName -Secret 'test' -Vault $script:TestVaultName

            $nestedPath | Should -Exist
            Join-Path $nestedPath "$($script:TestSecretName).yaml" | Should -Exist

            # Restore original vault configuration
            Unregister-SecretVault -Name $script:TestVaultName
            Register-SecretVault -Name $script:TestVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $script:TestSecretsPath
                FilePattern = '*.yaml'
                Recurse     = $false
            }
        }

        It 'File is readable by SOPS after creation' {
            Set-Secret -Name $script:TestSecretName -Secret 'verify-encryption' -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestSecretsPath "$($script:TestSecretName).yaml"

            $decrypted = sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0
            $decrypted | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Update Existing Secret' -Tag 'Updates' {
        BeforeEach {
            $script:TestSecretName = "update-test-$(New-Guid)"
            Set-Secret -Name $script:TestSecretName -Secret 'original-value' -Vault $script:TestVaultName
        }

        AfterEach {
            if ($script:TestSecretName -and (Get-SecretInfo -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue)) {
                Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Overwrites existing secret value' {
            Set-Secret -Name $script:TestSecretName -Secret 'updated-value' -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                value = 'updated-value'
            } | Should -Be $true
            $retrieved | Should -Not -Match 'original-value'
        }

        It 'Updates secret type (String to Hashtable)' {
            $newHash = @{ key1 = 'value1'; key2 = 'value2' }

            Set-Secret -Name $script:TestSecretName -Secret $newHash -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                key1 = 'value1'
                key2 = 'value2'
            } | Should -Be $true
        }

        It 'Maintains SOPS encryption after update' {
            Set-Secret -Name $script:TestSecretName -Secret 'updated-encrypted' -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestSecretsPath "$($script:TestSecretName).yaml"
            $content = Get-Content $filePath -Raw

            $content | Should -Match 'sops:'
            $content | Should -Match 'ENC\['
        }

        It 'Does not create duplicate files on update' {
            Set-Secret -Name $script:TestSecretName -Secret 'update1' -Vault $script:TestVaultName
            Set-Secret -Name $script:TestSecretName -Secret 'update2' -Vault $script:TestVaultName

            $files = Get-ChildItem -Path $script:TestSecretsPath -Filter "*$($script:TestSecretName)*"
            $files.Count | Should -Be 1
        }
    }

    Context 'Error Handling' -Tag 'ErrorHandling' {
        It 'Throws on invalid vault parameters' {
            $badVaultName = 'BadVault'
            Register-SecretVault -Name $badVaultName -ModuleName $modulePath -VaultParameters @{
                Path = 'C:\NonExistent\Path\That\Does\Not\Exist'
            } -ErrorAction SilentlyContinue

            { Set-Secret -Name 'test' -Secret 'value' -Vault $badVaultName -ErrorAction Stop } |
                Should -Throw '*Unable to add secret*'

            Unregister-SecretVault -Name $badVaultName -ErrorAction SilentlyContinue
        }

        It 'Throws on SOPS encryption failure' {
            $sopsConfigPath = Join-Path $script:TestSecretsPath '.sops.yaml'
            $sopsConfigPath = [System.IO.Path]::GetFullPath($sopsConfigPath)
            $originalConfig = Get-Content $sopsConfigPath -Raw
            Remove-Item $sopsConfigPath -Force

            try {
                { Set-Secret -Name 'test-fail' -Secret 'value' -Vault $script:TestVaultName -ErrorAction Stop } |
                    Should -Throw '*Unable to add secret*'
            }
            finally {
                $parentDir = Split-Path $sopsConfigPath -Parent
                if (-not (Test-Path $parentDir)) {
                    $null = New-Item -ItemType Directory -Path $parentDir -Force
                }
                Set-Content -Path $sopsConfigPath -Value $originalConfig -Force
            }
        }

        It 'Handles special characters in secret names' {
            $specialName = "test-special-chars_123"

            Set-Secret -Name $specialName -Secret 'value' -Vault $script:TestVaultName
            $retrieved = Get-Secret -Name $specialName -Vault $script:TestVaultName -AsPlainText

            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*value'

            Remove-Secret -Name $specialName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
        }
    }

    Context 'Kubernetes Secret Support' -Tag 'Kubernetes' {
        BeforeAll {
            $k8sPath = Join-Path $TestDrive 'k8s-secrets'
            $null = New-Item -Path $k8sPath -ItemType Directory -Force

            New-SopsConfig -Path $k8sPath -EncryptedRegex '^(data|stringData)$'

            $k8sVaultName = 'SopsK8sWriteVault'
            Register-SecretVault -Name $k8sVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $k8sPath
                FilePattern = '*.yaml'
            }

            $script:K8sVaultName = $k8sVaultName
            $script:K8sPath = $k8sPath
        }

        AfterAll {
            if ($script:K8sVaultName) {
                Unregister-SecretVault -Name $script:K8sVaultName -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            $script:TestK8sSecretName = "k8s-test-$(New-Guid)"
        }

        AfterEach {
            if ($script:TestK8sSecretName -and (Get-SecretInfo -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -ErrorAction SilentlyContinue)) {
                Remove-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Creates Kubernetes Secret manifest structure' {
            $k8sSecret = @{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = @{
                    name      = $script:TestK8sSecretName
                    namespace = 'default'
                }
                type       = 'Opaque'
                stringData = @{
                    'api-key'     = 'secret-api-key-value'
                    'db-password' = 'secret-db-password'
                }
            }

            Set-Secret -Name $script:TestK8sSecretName -Secret $k8sSecret -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                kind                     = 'Secret'
                'stringData.api-key'     = 'secret-api-key-value'
                'stringData.db-password' = 'secret-db-password'
            } | Should -Be $true
        }

        It 'Accepts YAML string input (e.g., from New-KubernetesSecret pipeline)' {
            $yamlString = @"
kind: Secret
apiVersion: v1
metadata:
  namespace: bar
  name: foo
stringData:
  foo: "0"
"@

            Set-Secret -Name $script:TestK8sSecretName -Secret $yamlString -Vault $script:K8sVaultName

            $filePath = Join-Path $script:K8sPath "$($script:TestK8sSecretName).yaml"
            $fileContent = Get-Content $filePath -Raw

            # Should NOT wrap YAML in a "value:" key
            $fileContent | Should -Not -Match 'value:\s*\|'
            $fileContent | Should -Not -Match 'value:\s*>\s*kind:'

            # Should have actual K8s structure
            $fileContent | Should -Match 'kind:\s*Secret'
            $fileContent | Should -Match 'apiVersion:\s*v1'
            $fileContent | Should -Match 'metadata:'
            $fileContent | Should -Match 'stringData:'

            # Decrypt and verify structure
            $decrypted = sops -d $filePath 2>&1 | Out-String
            $decrypted | Should -Match 'kind:\s*Secret'
            $decrypted | Should -Match 'stringData:'
            $decrypted | Should -Match 'foo:\s*[''"]0[''"]'

            if ($fileContent -match 'value:') {
                $fileContent | Should -Not -Match 'stringData:'
            }
        }
    }
}

Describe 'Remove-Secret' -Tag 'WriteSupport', 'Integration' {
    BeforeAll {
        $script:TestVaultName = 'SopsRemoveTestVault'
        $script:TestSecretsPath = Join-Path $TestDrive 'remove-secrets'
        $null = New-Item -Path $script:TestSecretsPath -ItemType Directory -Force

        New-SopsConfig -Path $script:TestSecretsPath

        Register-SecretVault -Name $script:TestVaultName -ModuleName $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
        }
    }

    AfterAll {
        if ($script:TestVaultName) {
            Unregister-SecretVault -Name $script:TestVaultName -ErrorAction SilentlyContinue
        }
    }

    Context 'Removing Existing Secret' -Tag 'BasicOperations' {
        BeforeEach {
            $script:TestSecretName = "remove-test-$(New-Guid)"
            Set-Secret -Name $script:TestSecretName -Secret 'to-be-removed' -Vault $script:TestVaultName
        }

        It 'Successfully removes existing secret' {
            Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName

            $secret = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            $secret | Should -BeNullOrEmpty
        }

        It 'Deletes SOPS file when secret removed' {
            Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestSecretsPath "$($script:TestSecretName).yaml"
            $filePath | Should -Not -Exist
        }

        It 'Secret no longer appears in Get-SecretInfo after removal' {
            Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName

            $secretInfo = Get-SecretInfo -Name $script:TestSecretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            $secretInfo | Should -BeNullOrEmpty
        }

        It 'Completes successfully on removal' {
            { Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName } | Should -Not -Throw
        }
    }

    Context 'Error Handling' -Tag 'ErrorHandling' {
        It 'Throws when secret does not exist' {
            { Remove-Secret -Name 'nonexistent-secret-12345' -Vault $script:TestVaultName -ErrorAction Stop } |
                Should -Throw '*Unable to remove secret*'
        }

        It 'Handles double removal gracefully' {
            $testName = "double-remove-$(New-Guid)"
            Set-Secret -Name $testName -Secret 'value' -Vault $script:TestVaultName

            { Remove-Secret -Name $testName -Vault $script:TestVaultName } | Should -Not -Throw

            { Remove-Secret -Name $testName -Vault $script:TestVaultName -ErrorAction Stop } |
                Should -Throw '*Unable to remove secret*'
        }

        It 'Handles special characters in secret name' {
            $specialName = "remove-special_chars-123"
            Set-Secret -Name $specialName -Secret 'value' -Vault $script:TestVaultName

            { Remove-Secret -Name $specialName -Vault $script:TestVaultName } | Should -Not -Throw

            Get-Secret -Name $specialName -Vault $script:TestVaultName -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }

    Context 'Kubernetes Secret Data Key Removal' -Tag 'Kubernetes' {
        BeforeAll {
            $k8sPath = Join-Path $TestDrive 'k8s-remove'
            $null = New-Item -Path $k8sPath -ItemType Directory -Force

            New-SopsConfig -Path $k8sPath

            $k8sVaultName = 'SopsK8sRemoveVault'
            Register-SecretVault -Name $k8sVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $k8sPath
                FilePattern = '*.yaml'
            }

            $script:K8sVaultName = $k8sVaultName
        }

        AfterAll {
            if ($script:K8sVaultName) {
                Unregister-SecretVault -Name $script:K8sVaultName -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            $script:TestK8sSecretName = "k8s-remove-$(New-Guid)"

            $k8sSecret = @{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = @{
                    name      = 'test-secret'
                    namespace = 'default'
                }
                type       = 'Opaque'
                stringData = @{
                    'host'     = 'postgres.example.com'
                    'username' = 'prod_user'
                    'password' = 'secretPass123'
                }
            }
            Set-Secret -Name $script:TestK8sSecretName -Secret $k8sSecret -Vault $script:K8sVaultName
        }

        AfterEach {
            if ($script:TestK8sSecretName -and (Get-SecretInfo -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -ErrorAction SilentlyContinue)) {
                Remove-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Removes individual key using path syntax with literal null' {
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'host:'
            $retrieved | Should -Match 'username:\s*prod_user'
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Removes individual key using path syntax with PowerShell $null' {
            ".stringData.username: `$null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'username:'
            $retrieved | Should -Match 'host:\s*postgres\.example\.com'
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Removes multiple keys sequentially' {
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName
            ".stringData.username: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'host:'
            $retrieved | Should -Not -Match 'username:'
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Does not set literal "null" string as value' {
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'host:\s*["]?null["]?'
            $retrieved | Should -Not -Match 'host:'
        }

        It 'Does not set empty string when using $null syntax' {
            ".stringData.password: `$null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'password:\s*["]?["]?'
            $retrieved | Should -Not -Match 'password:'
        }

        It 'Removes nested keys in structured secrets' {
            $nestedSecret = @{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = @{
                    name   = 'nested-test'
                    labels = @{
                        'app' = 'myapp'
                        'env' = 'prod'
                    }
                }
                stringData = @{
                    'api-key' = 'secret123'
                }
            }

            $nestedName = "nested-$(New-Guid)"
            Set-Secret -Name $nestedName -Secret $nestedSecret -Vault $script:K8sVaultName

            try {
                ".metadata.labels.env: null" | Set-Secret -Name $nestedName -Vault $script:K8sVaultName

                $retrieved = Get-Secret -Name $nestedName -Vault $script:K8sVaultName -AsPlainText
                $retrieved | Should -BeOfType [string]
                $retrieved | Should -Not -Match 'env:\s*prod'
                $retrieved | Should -Match 'app:\s*myapp'
                $retrieved | Should -Match 'api-key:\s*secret123'
            }
            finally {
                Remove-Secret -Name $nestedName -Vault $script:K8sVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Cleanup and File Management' -Tag 'FileOperations' {
        It 'Does not affect other secrets in same directory' {
            $secret1 = "shared-dir-1-$(New-Guid)"
            $secret2 = "shared-dir-2-$(New-Guid)"

            Set-Secret -Name $secret1 -Secret 'value1' -Vault $script:TestVaultName
            Set-Secret -Name $secret2 -Secret 'value2' -Vault $script:TestVaultName

            Remove-Secret -Name $secret1 -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $secret2 -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*value2'

            Remove-Secret -Name $secret2 -Vault $script:TestVaultName -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Write Support Integration Scenarios' -Tag 'WriteSupport', 'Integration', 'Scenarios' {
    BeforeAll {
        $script:ScenarioVaultName = 'SopsScenarioVault'
        $script:ScenarioPath = Join-Path $TestDrive 'scenarios'
        $null = New-Item -Path $script:ScenarioPath -ItemType Directory -Force

        New-SopsConfig -Path $script:ScenarioPath

        Register-SecretVault -Name $script:ScenarioVaultName -ModuleName $modulePath -VaultParameters @{
            Path        = $script:ScenarioPath
            FilePattern = '*.yaml'
        }
    }

    AfterAll {
        if ($script:ScenarioVaultName) {
            Unregister-SecretVault -Name $script:ScenarioVaultName -ErrorAction SilentlyContinue
        }
    }

    It 'Round-trip: Set, Get, Update, Get, Remove sequence' {
        $secretName = "roundtrip-$(New-Guid)"

        Set-Secret -Name $secretName -Secret 'initial' -Vault $script:ScenarioVaultName
        $value1 = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
        $value1 | Should -BeOfType [string]
        $value1 | Should -Match 'value:\s*initial'

        Set-Secret -Name $secretName -Secret 'updated' -Vault $script:ScenarioVaultName
        $value2 = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
        $value2 | Should -BeOfType [string]
        $value2 | Should -Match 'value:\s*updated'

        Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName
        $value3 = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
        $value3 | Should -BeNullOrEmpty
    }

    It 'Multiple secrets can coexist and be managed independently' {
        $secrets = @(
            @{ Name = "multi-1-$(New-Guid)"; Value = 'value1' }
            @{ Name = "multi-2-$(New-Guid)"; Value = 'value2' }
            @{ Name = "multi-3-$(New-Guid)"; Value = 'value3' }
        )

        try {
            foreach ($secret in $secrets) {
                Set-Secret -Name $secret.Name -Secret $secret.Value -Vault $script:ScenarioVaultName
            }

            foreach ($secret in $secrets) {
                $retrieved = Get-Secret -Name $secret.Name -Vault $script:ScenarioVaultName -AsPlainText
                $retrieved | Should -BeOfType [string]
                $retrieved | Should -Match "value:\s*$($secret.Value)"
            }

            Remove-Secret -Name $secrets[1].Name -Vault $script:ScenarioVaultName

            $retrieved1 = Get-Secret -Name $secrets[0].Name -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved1 | Should -BeOfType [string]
            $retrieved1 | Should -Match 'value:\s*value1'

            $retrieved3 = Get-Secret -Name $secrets[2].Name -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved3 | Should -BeOfType [string]
            $retrieved3 | Should -Match 'value:\s*value3'
        }
        finally {
            foreach ($secret in $secrets) {
                Remove-Secret -Name $secret.Name -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    It 'SOPS encryption is preserved across updates' {
        $secretName = "encryption-test-$(New-Guid)"

        try {
            Set-Secret -Name $secretName -Secret 'initial' -Vault $script:ScenarioVaultName
            $filePath = Join-Path $script:ScenarioPath "$secretName.yaml"
            (Get-Content $filePath -Raw) | Should -Match 'sops:'

            Set-Secret -Name $secretName -Secret 'updated' -Vault $script:ScenarioVaultName
            $content2 = Get-Content $filePath -Raw
            $content2 | Should -Match 'sops:'
            $content2 | Should -Match 'ENC\['

            $retrieved = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*updated'
        }
        finally {
            Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
        }
    }

    It 'Handles rapid create/update/delete operations' {
        $secretName = "rapid-ops-$(New-Guid)"

        try {
            Set-Secret -Name $secretName -Secret 'v1' -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v2' -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v3' -Vault $script:ScenarioVaultName
            Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v4' -Vault $script:ScenarioVaultName

            $retrieved = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*v4'
        }
        finally {
            Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
        }
    }
}
