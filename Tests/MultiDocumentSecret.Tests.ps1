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
}

AfterAll {
    Restore-TestEnvironment -State $script:testState
}

Describe 'Set-Secret with Multi-Document YAML' -Tag 'MultiDocument', 'Integration' {
    BeforeAll {
        $script:TestSecretsPath = Join-Path $TestDrive 'multidoc-secrets'
        $null = New-Item -Path $script:TestSecretsPath -ItemType Directory -Force

        # Create .sops.yaml with encrypted_regex for K8s secret encryption
        $testDataPath = Join-Path $PSScriptRoot 'TestData'
        $testKeyFile = Join-Path $testDataPath 'test-key.txt'

        if (Test-Path $testKeyFile) {
            $ageKeyContent = Get-Content $testKeyFile -Raw
            if ($ageKeyContent -match 'public key: (.+)') {
                $script:AgePublicKey = $Matches[1].Trim()
                $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $($script:AgePublicKey)
"@
                Set-Content -Path (Join-Path $script:TestSecretsPath '.sops.yaml') -Value $sopsConfig
            }
        }

        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsMultiDocTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
        }

        # Helper: create a multi-document encrypted test file
        function New-MultiDocTestFile {
            param(
                [string]$SecretName,
                [string[]]$Documents
            )

            $combined = $Documents -join "`n---`n"
            $filePath = Join-Path $script:TestSecretsPath "$SecretName.yaml"
            $insecurePath = Join-Path $script:TestSecretsPath "$SecretName.insecure.yaml"

            Set-Content -Path $insecurePath -Value $combined -NoNewline
            Move-Item -Path $insecurePath -Destination $filePath -Force

            $previousLocation = Get-Location
            try {
                Set-Location $script:TestSecretsPath
                $relativePath = [System.IO.Path]::GetRelativePath($script:TestSecretsPath, $filePath)
                $null = & sops --encrypt --in-place $relativePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "SOPS encryption failed for multi-doc file: $filePath"
                }
            }
            finally {
                Set-Location $previousLocation
            }

            return $filePath
        }

        # Helper: retrieve and parse multi-document secret into array of hashtables
        function Get-ParsedMultiDocSecret {
            param([string]$SecretName)

            $retrieved = Get-Secret -Name $SecretName -Vault $script:TestVaultName -AsPlainText
            Import-Module powershell-yaml -ErrorAction Stop
            ($retrieved -split '(?m)^---\s*$') |
                Where-Object { $_.Trim() } |
                ForEach-Object { $_ | ConvertFrom-Yaml }
        }

        # Standard two-document test fixtures
        $script:Doc1 = @"
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: production
stringData:
  username: prod_user
  password: OldDbPass123
"@

        $script:Doc2 = @"
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
  namespace: production
stringData:
  primary-key: old-api-key-1
  secondary-key: old-api-key-2
"@
    }

    AfterAll {
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'Auto-detect targeting by key path' -Tag 'AutoDetect' {
        It 'Updates key in second document when path exists only there' {
            $secretName = "autodetect-second-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.primary-key: new-api-key-value" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[1].stringData.'primary-key' | Should -Be 'new-api-key-value'
            $docs[1].stringData.'secondary-key' | Should -Be 'old-api-key-2'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
        }

        It 'Updates key in first document when path exists only there' {
            $secretName = "autodetect-first-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.password: NewDbPass456" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[0].stringData.password | Should -Be 'NewDbPass456'
            $docs[0].stringData.username | Should -Be 'prod_user'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }

        It 'Preserves unmodified document data after update' {
            $secretName = "preserve-data-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.primary-key: updated-key" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[0].stringData.username | Should -Be 'prod_user'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[0].metadata.name | Should -Be 'db-credentials'

            $filePath = Join-Path $script:TestSecretsPath "$secretName.yaml"
            (Get-Content -Path $filePath -Raw) | Should -Match 'ENC\['
        }

        It 'Handles YAML patching mode on multi-doc files' {
            $secretName = "yaml-patch-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            $yamlPatch = @"
stringData:
  password: patched-password
  username: patched-user
"@
            $yamlPatch | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[0].stringData.password | Should -Be 'patched-password'
            $docs[0].stringData.username | Should -Be 'patched-user'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }
    }

    Context 'Explicit DocumentName targeting' -Tag 'DocumentName' {
        It 'Targets document by metadata.name' {
            $secretName = "docname-target-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.primary-key: explicit-value" | Set-Secret -Name $secretName -Vault $script:TestVaultName -Metadata @{ DocumentName = 'api-keys' }

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[1].stringData.'primary-key' | Should -Be 'explicit-value'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
        }

        It 'DocumentName allows adding new key to specific document' {
            $secretName = "docname-newkey-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.new-field: added-value" | Set-Secret -Name $secretName -Vault $script:TestVaultName -Metadata @{ DocumentName = 'api-keys' }

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[1].stringData.'new-field' | Should -Be 'added-value'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }
    }

    Context 'Error handling' -Tag 'Errors' {
        It 'Errors when key path not found in any document' {
            $secretName = "error-notfound-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            $Error.Clear()
            {
                ".stringData.nonexistent-key: value" | Set-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction Stop
            } | Should -Throw '*Unable to add secret*'

            $innerErrors = $Error | ForEach-Object { $_.Exception.InnerException.Message } | Where-Object { $_ }
            $innerErrors | Should -Contain ($innerErrors | Where-Object { $_ -match 'not found in any document' } | Select-Object -First 1)
        }

        It 'Errors when key path found in multiple documents' {
            $secretName = "error-ambiguous-$(New-Guid)"

            $docWithShared1 = @"
apiVersion: v1
kind: Secret
metadata:
  name: shared-one
  namespace: test
stringData:
  shared-key: value1
"@
            $docWithShared2 = @"
apiVersion: v1
kind: Secret
metadata:
  name: shared-two
  namespace: test
stringData:
  shared-key: value2
"@
            New-MultiDocTestFile -SecretName $secretName -Documents @($docWithShared1, $docWithShared2)

            $Error.Clear()
            {
                ".stringData.shared-key: new-value" | Set-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction Stop
            } | Should -Throw '*Unable to add secret*'

            $innerErrors = $Error | ForEach-Object { $_.Exception.InnerException.Message } | Where-Object { $_ }
            $innerErrors | Should -Contain ($innerErrors | Where-Object { $_ -match 'multiple documents' } | Select-Object -First 1)
        }

        It 'Errors when DocumentName does not match any document' {
            $secretName = "error-badname-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            $Error.Clear()
            {
                ".stringData.password: value" | Set-Secret -Name $secretName -Vault $script:TestVaultName -Metadata @{ DocumentName = 'nonexistent-doc' } -ErrorAction Stop
            } | Should -Throw '*Unable to add secret*'

            $innerErrors = $Error | ForEach-Object { $_.Exception.InnerException.Message } | Where-Object { $_ }
            $innerErrors | Should -Contain ($innerErrors | Where-Object { $_ -match 'No document found with metadata.name' } | Select-Object -First 1)
        }
    }

    Context 'Unset operations in multi-document files' -Tag 'Unset' {
        It 'Removes key from correct document using null syntax' {
            $secretName = "unset-null-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            ".stringData.password: null" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[0].stringData.ContainsKey('password') | Should -Be $false
            $docs[0].stringData.username | Should -Be 'prod_user'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }
    }

    Context 'Single-document regression' -Tag 'Regression' {
        It 'Single-document files work unchanged' {
            $secretName = "single-doc-$(New-Guid)"

            $k8sSecret = @{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = @{
                    name      = 'single-secret'
                    namespace = 'default'
                }
                stringData = @{
                    password = 'original-pass'
                    username = 'admin'
                }
            }
            Set-Secret -Name $secretName -Secret $k8sSecret -Vault $script:TestVaultName

            ".stringData.password: updated-pass" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                'stringData.password' = 'updated-pass'
                'stringData.username' = 'admin'
            } | Should -Be $true
        }
    }

    Context 'Append new document via complete K8s secret' -Tag 'Append' {
        $script:KubectlAvailable = $null -ne (Get-Command 'kubectl' -ErrorAction SilentlyContinue)

        It 'Appends new document when metadata.name does not exist in multi-doc file' -Skip:(-not $script:KubectlAvailable) {
            $secretName = "append-new-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            New-KubernetesSecret -Name 'cache-config' -FromLiteral @{ 'redis-url' = 'redis://cache:6379' } |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 3
            $docs[0].metadata.name | Should -Be 'db-credentials'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[1].metadata.name | Should -Be 'api-keys'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
            $docs[2].metadata.name | Should -Be 'cache-config'
            $docs[2].stringData.'redis-url' | Should -Be 'redis://cache:6379'

            $filePath = Join-Path $script:TestSecretsPath "$secretName.yaml"
            (Get-Content -Path $filePath -Raw) | Should -Match 'ENC\['
        }

        It 'Merges into existing document when metadata.name matches' -Skip:(-not $script:KubectlAvailable) {
            $secretName = "append-merge-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            New-KubernetesSecret -Name 'db-credentials' -FromLiteral @{
                'password'    = 'UpdatedDbPass789'
                'extra-field' = 'merged-value'
            } | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 2
            $docs[0].metadata.name | Should -Be 'db-credentials'
            $docs[0].stringData.password | Should -Be 'UpdatedDbPass789'
            $docs[0].stringData.'extra-field' | Should -Be 'merged-value'
            $docs[0].stringData.username | Should -Be 'prod_user'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }

        It 'Appends a hashtable complete document when metadata.name is absent from file' {
            $secretName = "append-ht-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            $newDoc = [ordered]@{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = [ordered]@{ name = 'tls-config' }
                stringData = [ordered]@{ cert = 'CERTDATA' }
            }
            Set-Secret -Name $secretName -Secret $newDoc -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 3
            $docs[2].metadata.name | Should -Be 'tls-config'
            $docs[2].stringData.cert | Should -Be 'CERTDATA'
        }
    }

    Context 'Edge cases' -Tag 'EdgeCases' {
        It 'Handles three or more documents' {
            $secretName = "three-docs-$(New-Guid)"

            $doc3 = @"
apiVersion: v1
kind: Secret
metadata:
  name: cache-config
  namespace: production
stringData:
  redis-url: redis://localhost:6379
  ttl: "3600"
"@
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2, $doc3)

            ".stringData.primary-key: updated-in-middle" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 3
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[1].stringData.'primary-key' | Should -Be 'updated-in-middle'
            $docs[2].stringData.'redis-url' | Should -Be 'redis://localhost:6379'
        }
    }
}
