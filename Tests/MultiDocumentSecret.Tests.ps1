#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for Set-Secret multi-document YAML support.

.DESCRIPTION
    Validates that Set-Secret correctly handles YAML files containing multiple
    documents separated by '---'. Tests cover:
    - Auto-detection of target document by key path
    - Explicit targeting by metadata.name via -Metadata
    - Error handling for ambiguous or missing paths
    - Key removal (unset) in multi-document files
    - Single-document regression
    - Three or more documents

.NOTES
    Run with: Invoke-Pester -Path .\Tests\MultiDocumentSecret.Tests.ps1 -Tag 'MultiDocument'
#>

BeforeAll {
    # Import test helpers for isolation utilities
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    # Auto-bootstrap test data if missing
    if (-not (Initialize-TestDataIfMissing)) {
        throw "Cannot run tests: Test data initialization failed. Please ensure SOPS and age are installed."
    }

    # Clean up any orphaned test vaults from previous runs
    Remove-OrphanedTestVaults

    # Save environment state (location, environment variables, registered vaults)
    $script:testState = Initialize-TestEnvironment

    # Import the main module
    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    # Import SecretManagement module
    if (-not (Get-Module Microsoft.PowerShell.SecretManagement -ListAvailable)) {
        throw "Microsoft.PowerShell.SecretManagement module is required. Install with: Install-Module Microsoft.PowerShell.SecretManagement"
    }
    Import-Module Microsoft.PowerShell.SecretManagement -Force

    # Configure test-specific age key in isolated environment
    $testDataPath = Join-Path $PSScriptRoot 'TestData'
    $testKeyFile = Join-Path $testDataPath 'test-key.txt'
    if (Test-Path $testKeyFile) {
        $env:SOPS_AGE_KEY_FILE = $testKeyFile
        Write-Verbose "Configured test-isolated SOPS_AGE_KEY_FILE: $testKeyFile"
    }
    else {
        throw "Test key file not found: $testKeyFile"
    }
}

AfterAll {
    # Restore environment state (location, environment variables, cleanup test vaults)
    Restore-TestEnvironment -State $script:testState
}

Describe 'Set-Secret with Multi-Document YAML' -Tag 'MultiDocument', 'Integration' {
    BeforeAll {
        # Create test vault
        $script:TestSecretsPath = Join-Path $TestDrive 'multidoc-secrets'
        New-Item -Path $script:TestSecretsPath -ItemType Directory -Force | Out-Null

        # Create .sops.yaml with encrypted_regex for realistic K8s secret encryption
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

        # Register vault with unique isolated name
        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsMultiDocTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
        }
        Write-Verbose "Registered isolated test vault: $script:TestVaultName"

        # Helper function: create a multi-document encrypted test file
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
                & sops --encrypt --in-place $relativePath 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "SOPS encryption failed for multi-doc file: $filePath"
                }
            }
            finally {
                Set-Location $previousLocation
            }

            return $filePath
        }

        # Helper function: retrieve and parse multi-document secret into array of hashtables
        function Get-ParsedMultiDocSecret {
            param([string]$SecretName)

            $retrieved = Get-Secret -Name $SecretName -Vault $script:TestVaultName -AsPlainText
            Import-Module powershell-yaml -ErrorAction Stop
            ($retrieved -split '(?m)^---\s*$') |
                Where-Object { $_.Trim() } |
                ForEach-Object { $_ | ConvertFrom-Yaml }
        }

        # Standard two-document test fixture
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

            # Update doc2 only
            ".stringData.primary-key: updated-key" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs[0].stringData.username | Should -Be 'prod_user'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[0].metadata.name | Should -Be 'db-credentials'

            # File should still be encrypted
            $filePath = Join-Path $script:TestSecretsPath "$secretName.yaml"
            $content = Get-Content -Path $filePath -Raw
            $content | Should -Match 'ENC\['
        }

        It 'Handles YAML patching mode on multi-doc files' {
            $secretName = "yaml-patch-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            # Patch using YAML content - both keys exist only in doc1
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

            # Verify inner error contains our specific message
            $innerErrors = $Error | ForEach-Object { $_.Exception.InnerException.Message } | Where-Object { $_ }
            $innerErrors | Should -Contain ($innerErrors | Where-Object { $_ -match 'not found in any document' } | Select-Object -First 1)
        }

        It 'Errors when key path found in multiple documents' {
            $secretName = "error-ambiguous-$(New-Guid)"

            # Create two docs that both have stringData.shared-key
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

            # Create a standard single-document secret
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

            # Update using path syntax (single-doc, should work as before)
            ".stringData.password: updated-pass" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            Test-YamlContent -YamlContent $retrieved -ExpectedValues @{
                'stringData.password' = 'updated-pass'
                'stringData.username' = 'admin'
            } | Should -Be $true
        }
    }

    Context 'Append new document via complete K8s secret' -Tag 'Append' {
        BeforeAll {
            $script:KubectlAvailable = $null -ne (Get-Command 'kubectl' -ErrorAction SilentlyContinue)
        }

        It 'Appends new document when metadata.name does not exist in multi-doc file' -Skip:(-not $script:KubectlAvailable) {
            $secretName = "append-new-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            # Pipe a brand-new K8s Secret into the existing multi-doc file
            New-KubernetesSecret -Name 'cache-config' -FromLiteral @{ 'redis-url' = 'redis://cache:6379' } |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 3
            # Original docs are untouched
            $docs[0].metadata.name | Should -Be 'db-credentials'
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[1].metadata.name | Should -Be 'api-keys'
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
            # New doc is appended
            $docs[2].metadata.name | Should -Be 'cache-config'
            $docs[2].stringData.'redis-url' | Should -Be 'redis://cache:6379'

            # File must still be encrypted
            $filePath = Join-Path $script:TestSecretsPath "$secretName.yaml"
            $rawContent = Get-Content -Path $filePath -Raw
            $rawContent | Should -Match 'ENC\['
        }

        It 'Merges into existing document when metadata.name matches' -Skip:(-not $script:KubectlAvailable) {
            $secretName = "append-merge-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            # Pipe a new manifest for an already-present name; a new key should be merged in
            New-KubernetesSecret -Name 'db-credentials' -FromLiteral @{
                'password'    = 'UpdatedDbPass789'
                'extra-field' = 'merged-value'
            } | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 2
            $docs[0].metadata.name | Should -Be 'db-credentials'
            $docs[0].stringData.password | Should -Be 'UpdatedDbPass789'
            $docs[0].stringData.'extra-field' | Should -Be 'merged-value'
            # Pre-existing key preserved because merge/patch keeps unmentioned keys
            $docs[0].stringData.username | Should -Be 'prod_user'
            # Second document untouched
            $docs[1].stringData.'primary-key' | Should -Be 'old-api-key-1'
        }

        It 'Appends a hashtable complete document when metadata.name is absent from file' {
            $secretName = "append-ht-$(New-Guid)"
            New-MultiDocTestFile -SecretName $secretName -Documents @($script:Doc1, $script:Doc2)

            $newDoc = [ordered]@{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = [ordered]@{
                    name = 'tls-config'
                }
                stringData = [ordered]@{
                    cert = 'CERTDATA'
                }
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

            # Update the middle document
            ".stringData.primary-key: updated-in-middle" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $docs = Get-ParsedMultiDocSecret -SecretName $secretName

            $docs.Count | Should -Be 3
            $docs[0].stringData.password | Should -Be 'OldDbPass123'
            $docs[1].stringData.'primary-key' | Should -Be 'updated-in-middle'
            $docs[2].stringData.'redis-url' | Should -Be 'redis://localhost:6379'
        }
    }
}
