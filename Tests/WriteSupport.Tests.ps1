#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Phase 3 Write Support Tests for SecretManagement.Sops

.DESCRIPTION
    Comprehensive test suite for Set-Secret and Remove-Secret operations.
    These tests validate write functionality including:
    - Creating new SOPS-encrypted secrets
    - Updating existing secrets
    - Removing secrets
    - File management operations
    - SOPS encryption/decryption round-trips
    - All supported secret types
    - Error handling and edge cases

.NOTES
    Run with: Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -Tag 'WriteSupport'
    Skip write tests: Invoke-Pester -ExcludeTag 'WriteSupport'
#>

BeforeAll {
    # Import test helpers for isolation utilities
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    # Clean up any orphaned test vaults from previous runs
    Remove-OrphanedTestVaults

    # Save original environment state
    $script:OriginalEnvironment = Save-SopsEnvironment

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
    # Restore original environment state
    if ($script:OriginalEnvironment) {
        Restore-SopsEnvironment -State $script:OriginalEnvironment
    }
}

Describe 'Set-Secret' -Tag 'WriteSupport', 'Integration' {
    BeforeAll {
        # Create test vault in TestDrive
        $script:TestSecretsPath = Join-Path $TestDrive 'secrets'
        New-Item -Path $script:TestSecretsPath -ItemType Directory -Force | Out-Null

        # Create .sops.yaml configuration in test vault
        $testDataPath = Join-Path $PSScriptRoot 'TestData'
        $testKeyFile = Join-Path $testDataPath 'test-key.txt'

        if (Test-Path $testKeyFile) {
            # Read the age public key from the test key file
            $ageKeyContent = Get-Content $testKeyFile -Raw
            if ($ageKeyContent -match 'public key: (.+)') {
                $agePublicKey = $Matches[1].Trim()

                # Create .sops.yaml in test vault
                $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
                Set-Content -Path (Join-Path $script:TestSecretsPath '.sops.yaml') -Value $sopsConfig
            }
        }

        # Register vault with unique isolated name
        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsWriteTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
            Recurse     = $false
        }
        Write-Verbose "Registered isolated test vault: $script:TestVaultName"
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
                    # Expected if test didn't create the secret
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
            # Should return raw YAML string with {value: ...} wrapper
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match "value:\s*$testValue"
        }

        It 'Supports SecureString secret type' {
            $testValue = ConvertTo-SecureString 'secure-password-123' -AsPlainText -Force

            Set-Secret -Name $script:TestSecretName -Secret $testValue -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            # Should return raw YAML string with {value: ...} wrapper
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*secure-password-123'
        }

        It 'Supports PSCredential secret type' {
            $testCred = [PSCredential]::new('testuser', (ConvertTo-SecureString 'testpass123' -AsPlainText -Force))

            Set-Secret -Name $script:TestSecretName -Secret $testCred -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            # Should return raw YAML string with username/password fields
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'username:\s*testuser'
            $retrieved | Should -Match 'password:\s*testpass123'
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
            # Should return raw YAML string with all hashtable fields
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'database_host:\s*postgres\.example\.com'
            $retrieved | Should -Match 'database_port:\s*5432'
            $retrieved | Should -Match 'database_name:\s*production'
            $retrieved | Should -Match 'ssl_enabled:\s*true'
        }

        It 'Supports byte array secret type' {
            $testBytes = [System.Text.Encoding]::UTF8.GetBytes('binary-content-data')

            Set-Secret -Name $script:TestSecretName -Secret $testBytes -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            # Should return raw YAML string with base64-encoded content
            $retrieved | Should -BeOfType [string]
            # Byte arrays are stored as base64 in YAML
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

            # SOPS-encrypted files contain metadata
            $content | Should -Match 'sops:'
            $content | Should -Match 'version:'

            # Should contain encrypted data (ENC[...] format)
            $content | Should -Match 'ENC\['
        }

        It 'Creates directory structure if missing' {
            $nestedPath = Join-Path $script:TestSecretsPath 'nested\deep\path'
            # Create the vault base path (vault path must exist)
            New-Item -Path $nestedPath -ItemType Directory -Force | Out-Null

            # Create .sops.yaml in the nested vault path
            $sopsConfigContent = Get-Content (Join-Path $script:TestSecretsPath '.sops.yaml') -Raw
            Set-Content -Path (Join-Path $nestedPath '.sops.yaml') -Value $sopsConfigContent

            # Update vault to point to nested location
            Unregister-SecretVault -Name $script:TestVaultName
            Register-SecretVault -Name $script:TestVaultName -ModuleName $modulePath -VaultParameters @{
                Path        = $nestedPath
                FilePattern = '*.yaml'
            }

            Set-Secret -Name $script:TestSecretName -Secret 'test' -Vault $script:TestVaultName

            $nestedPath | Should -Exist
            Join-Path $nestedPath "$($script:TestSecretName).yaml" | Should -Exist

            # Restore original vault configuration for subsequent tests
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

            # Verify SOPS can decrypt what we just created
            $decrypted = sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0
            $decrypted | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Update Existing Secret' -Tag 'Updates' {
        BeforeEach {
            $script:TestSecretName = "update-test-$(New-Guid)"
            # Pre-create a secret
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
            # Should return raw YAML string
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*updated-value'
            $retrieved | Should -Not -Match 'original-value'
        }

        It 'Updates secret type (String to Hashtable)' {
            $newHash = @{ key1 = 'value1'; key2 = 'value2' }

            Set-Secret -Name $script:TestSecretName -Secret $newHash -Vault $script:TestVaultName

            $retrieved = Get-Secret -Name $script:TestSecretName -Vault $script:TestVaultName -AsPlainText
            # Should return raw YAML string with hashtable fields
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'key1:\s*value1'
            $retrieved | Should -Match 'key2:\s*value2'
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
            # Register vault with invalid path
            $badVaultName = 'BadVault'
            Register-SecretVault -Name $badVaultName -ModuleName $modulePath -VaultParameters @{
                Path = 'C:\NonExistent\Path\That\Does\Not\Exist'
            } -ErrorAction SilentlyContinue

            { Set-Secret -Name 'test' -Secret 'value' -Vault $badVaultName -ErrorAction Stop } |
                Should -Throw

            Unregister-SecretVault -Name $badVaultName -ErrorAction SilentlyContinue
        }

        It 'Throws on SOPS encryption failure' {
            # Temporarily break SOPS configuration by removing .sops.yaml
            $sopsConfigPath = Join-Path $script:TestSecretsPath '.sops.yaml'
            $originalConfig = Get-Content $sopsConfigPath -Raw
            Remove-Item $sopsConfigPath

            try {
                { Set-Secret -Name 'test-fail' -Secret 'value' -Vault $script:TestVaultName -ErrorAction Stop } |
                    Should -Throw
            }
 finally {
                # Restore .sops.yaml
                Set-Content -Path $sopsConfigPath -Value $originalConfig
            }
        }

        It 'Handles special characters in secret names' {
            $specialName = "test-special-chars_123"

            Set-Secret -Name $specialName -Secret 'value' -Vault $script:TestVaultName
            $retrieved = Get-Secret -Name $specialName -Vault $script:TestVaultName -AsPlainText

            # Should return raw YAML string
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*value'

            Remove-Secret -Name $specialName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
        }

        It 'Handles empty string secret' {
            $emptyName = "test-empty-$(New-Guid)"

            Set-Secret -Name $emptyName -Secret '' -Vault $script:TestVaultName
            $retrieved = Get-Secret -Name $emptyName -Vault $script:TestVaultName -AsPlainText

            # Should return raw YAML string with empty value
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*[''"]?[''"]?'

            Remove-Secret -Name $emptyName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
        }
    }

    Context 'Kubernetes Secret Support' -Tag 'Kubernetes' {
        BeforeAll {
            # Register vault for K8s secrets (no special mode - just regular SOPS encryption)
            $k8sVaultName = 'SopsK8sWriteVault'
            $k8sPath = Join-Path $TestDrive 'k8s-secrets'
            New-Item -Path $k8sPath -ItemType Directory -Force | Out-Null

            # Create .sops.yaml configuration
            $testDataPath = Join-Path $PSScriptRoot 'TestData'
            $testKeyFile = Join-Path $testDataPath 'test-key.txt'
            if (Test-Path $testKeyFile) {
                $ageKeyContent = Get-Content $testKeyFile -Raw
                if ($ageKeyContent -match 'public key: (.+)') {
                    $agePublicKey = $Matches[1].Trim()
                    $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $agePublicKey
"@
                    Set-Content -Path (Join-Path $k8sPath '.sops.yaml') -Value $sopsConfig
                }
            }

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
            # Should return raw YAML string with K8s manifest structure
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'kind:\s*Secret'
            $retrieved | Should -Match 'api-key:\s*secret-api-key-value'
            $retrieved | Should -Match 'db-password:\s*secret-db-password'
        }

        It 'Accepts YAML string input (e.g., from New-KubernetesSecret pipeline)' {
            # Simulate New-KubernetesSecret output - a YAML string
            $yamlString = @"
kind: Secret
apiVersion: v1
metadata:
  namespace: bar
  name: foo
stringData:
  foo: "0"
"@

            # This should parse the YAML and store it as a structured K8s secret,
            # NOT wrap it in a { value: "kind: Secret\n..." } structure
            Set-Secret -Name $script:TestK8sSecretName -Secret $yamlString -Vault $script:K8sVaultName

            # Verify the file structure
            $filePath = Join-Path $script:K8sPath "$($script:TestK8sSecretName).yaml"
            $fileContent = Get-Content $filePath -Raw

            # Should NOT have a "value:" wrapper with the YAML as a string literal
            $fileContent | Should -Not -Match 'value:\s*\|'
            $fileContent | Should -Not -Match 'value:\s*>\s*kind:'

            # Should have the actual K8s structure
            $fileContent | Should -Match 'kind:\s*Secret'
            $fileContent | Should -Match 'apiVersion:\s*v1'
            $fileContent | Should -Match 'metadata:'
            $fileContent | Should -Match 'stringData:'

            # Decrypt and verify structure
            $decrypted = sops -d $filePath 2>&1 | Out-String
            $decrypted | Should -Match 'kind:\s*Secret'
            $decrypted | Should -Match 'stringData:'
            $decrypted | Should -Match 'foo:\s*[''"]0[''"]'

            # Should NOT have duplicate fields (both value: and stringData:)
            if ($fileContent -match 'value:') {
                $fileContent | Should -Not -Match 'stringData:'
            }
        }

    }
}

Describe 'Remove-Secret' -Tag 'WriteSupport', 'Integration' {
    BeforeAll {
        # Create test vault
        $script:TestVaultName = 'SopsRemoveTestVault'
        $script:TestSecretsPath = Join-Path $TestDrive 'remove-secrets'
        New-Item -Path $script:TestSecretsPath -ItemType Directory -Force | Out-Null

        # Create .sops.yaml configuration in test vault
        $testDataPath = Join-Path $PSScriptRoot 'TestData'
        $testKeyFile = Join-Path $testDataPath 'test-key.txt'

        if (Test-Path $testKeyFile) {
            # Read the age public key from the test key file
            $ageKeyContent = Get-Content $testKeyFile -Raw
            if ($ageKeyContent -match 'public key: (.+)') {
                $agePublicKey = $Matches[1].Trim()

                # Create .sops.yaml in test vault
                $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
                Set-Content -Path (Join-Path $script:TestSecretsPath '.sops.yaml') -Value $sopsConfig
            }
        }

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
            # Pre-create a secret to remove
            Set-Secret -Name $script:TestSecretName -Secret 'to-be-removed' -Vault $script:TestVaultName
        }

        It 'Successfully removes existing secret' {
            Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName

            # Verify secret is gone
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
            # Should not throw
            { Remove-Secret -Name $script:TestSecretName -Vault $script:TestVaultName } | Should -Not -Throw
        }
    }

    Context 'Error Handling' -Tag 'ErrorHandling' {
        It 'Throws when secret does not exist' {
            { Remove-Secret -Name 'nonexistent-secret-12345' -Vault $script:TestVaultName -ErrorAction Stop } |
                Should -Throw
        }

        It 'Handles double removal gracefully' {
            $testName = "double-remove-$(New-Guid)"
            Set-Secret -Name $testName -Secret 'value' -Vault $script:TestVaultName

            # First removal should succeed
            { Remove-Secret -Name $testName -Vault $script:TestVaultName } | Should -Not -Throw

            # Second removal should throw
            { Remove-Secret -Name $testName -Vault $script:TestVaultName -ErrorAction Stop } |
                Should -Throw
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
            $k8sVaultName = 'SopsK8sRemoveVault'
            $k8sPath = Join-Path $TestDrive 'k8s-remove'
            New-Item -Path $k8sPath -ItemType Directory -Force | Out-Null

            # Create .sops.yaml configuration in k8s vault
            $testDataPath = Join-Path $PSScriptRoot 'TestData'
            $testKeyFile = Join-Path $testDataPath 'test-key.txt'

            if (Test-Path $testKeyFile) {
                # Read the age public key from the test key file
                $ageKeyContent = Get-Content $testKeyFile -Raw
                if ($ageKeyContent -match 'public key: (.+)') {
                    $agePublicKey = $Matches[1].Trim()

                    # Create .sops.yaml in k8s vault
                    $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
                    Set-Content -Path (Join-Path $k8sPath '.sops.yaml') -Value $sopsConfig
                }
            }

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

            # Pre-create a K8s secret with multiple keys
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
            # Remove the 'host' key using path syntax
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Verify the key was removed
            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'host:'

            # Other keys should still exist
            $retrieved | Should -Match 'username:\s*prod_user'
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Removes individual key using path syntax with PowerShell $null' {
            # Remove the 'username' key using PowerShell null variable syntax
            ".stringData.username: `$null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Verify the key was removed
            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'username:'

            # Other keys should still exist
            $retrieved | Should -Match 'host:\s*postgres\.example\.com'
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Removes multiple keys sequentially' {
            # Remove host first
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Remove username next
            ".stringData.username: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Verify both keys were removed
            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Not -Match 'host:'
            $retrieved | Should -Not -Match 'username:'

            # Password should still exist
            $retrieved | Should -Match 'password:\s*secretPass123'
        }

        It 'Does not set literal "null" string as value' {
            # This test ensures we don't regress to setting "null" as a string value
            ".stringData.host: null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Verify the key was completely removed (not set to "null" string)
            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]

            # Should NOT have 'host: "null"' or 'host: null' in the output
            $retrieved | Should -Not -Match 'host:\s*["]?null["]?'

            # The key should be completely absent
            $retrieved | Should -Not -Match 'host:'
        }

        It 'Does not set empty string when using $null syntax' {
            # This test ensures we don't set empty string "" instead of removing
            ".stringData.password: `$null" | Set-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName

            # Verify the key was completely removed (not set to empty string)
            $retrieved = Get-Secret -Name $script:TestK8sSecretName -Vault $script:K8sVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]

            # Should NOT have 'password: ""' in the output
            $retrieved | Should -Not -Match 'password:\s*["]?["]?'

            # The key should be completely absent
            $retrieved | Should -Not -Match 'password:'
        }

        It 'Removes nested keys in structured secrets' {
            # Create a secret with nested structure
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
                # Remove a nested label
                ".metadata.labels.env: null" | Set-Secret -Name $nestedName -Vault $script:K8sVaultName

                # Verify the nested key was removed
                $retrieved = Get-Secret -Name $nestedName -Vault $script:K8sVaultName -AsPlainText
                $retrieved | Should -BeOfType [string]
                $retrieved | Should -Not -Match 'env:\s*prod'

                # Other nested keys should still exist
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

            # Remove first secret
            Remove-Secret -Name $secret1 -Vault $script:TestVaultName

            # Second secret should still exist
            $retrieved = Get-Secret -Name $secret2 -Vault $script:TestVaultName -AsPlainText
            # Should return raw YAML string
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*value2'

            # Cleanup
            Remove-Secret -Name $secret2 -Vault $script:TestVaultName -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Write Support Integration Scenarios' -Tag 'WriteSupport', 'Integration', 'Scenarios' {
    BeforeAll {
        $script:ScenarioVaultName = 'SopsScenarioVault'
        $script:ScenarioPath = Join-Path $TestDrive 'scenarios'
        New-Item -Path $script:ScenarioPath -ItemType Directory -Force | Out-Null

        # Create .sops.yaml configuration in test vault
        $testDataPath = Join-Path $PSScriptRoot 'TestData'
        $testKeyFile = Join-Path $testDataPath 'test-key.txt'

        if (Test-Path $testKeyFile) {
            # Read the age public key from the test key file
            $ageKeyContent = Get-Content $testKeyFile -Raw
            if ($ageKeyContent -match 'public key: (.+)') {
                $agePublicKey = $Matches[1].Trim()

                # Create .sops.yaml in test vault
                $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
                Set-Content -Path (Join-Path $script:ScenarioPath '.sops.yaml') -Value $sopsConfig
            }
        }

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

        # Create
        Set-Secret -Name $secretName -Secret 'initial' -Vault $script:ScenarioVaultName
        $value1 = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
        # Should return raw YAML string
        $value1 | Should -BeOfType [string]
        $value1 | Should -Match 'value:\s*initial'

        # Update
        Set-Secret -Name $secretName -Secret 'updated' -Vault $script:ScenarioVaultName
        $value2 = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
        # Should return raw YAML string
        $value2 | Should -BeOfType [string]
        $value2 | Should -Match 'value:\s*updated'

        # Remove
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
            # Create all
            foreach ($secret in $secrets) {
                Set-Secret -Name $secret.Name -Secret $secret.Value -Vault $script:ScenarioVaultName
            }

            # Verify all exist
            foreach ($secret in $secrets) {
                $retrieved = Get-Secret -Name $secret.Name -Vault $script:ScenarioVaultName -AsPlainText
                # Should return raw YAML string
                $retrieved | Should -BeOfType [string]
                $retrieved | Should -Match "value:\s*$($secret.Value)"
            }

            # Remove one
            Remove-Secret -Name $secrets[1].Name -Vault $script:ScenarioVaultName

            # Verify others still exist
            $retrieved1 = Get-Secret -Name $secrets[0].Name -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved1 | Should -BeOfType [string]
            $retrieved1 | Should -Match 'value:\s*value1'

            $retrieved3 = Get-Secret -Name $secrets[2].Name -Vault $script:ScenarioVaultName -AsPlainText
            $retrieved3 | Should -BeOfType [string]
            $retrieved3 | Should -Match 'value:\s*value3'

        }
 finally {
            # Cleanup
            foreach ($secret in $secrets) {
                Remove-Secret -Name $secret.Name -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    It 'SOPS encryption is preserved across updates' {
        $secretName = "encryption-test-$(New-Guid)"

        try {
            # Create
            Set-Secret -Name $secretName -Secret 'initial' -Vault $script:ScenarioVaultName
            $filePath = Join-Path $script:ScenarioPath "$secretName.yaml"
            $content1 = Get-Content $filePath -Raw
            $content1 | Should -Match 'sops:'

            # Update
            Set-Secret -Name $secretName -Secret 'updated' -Vault $script:ScenarioVaultName
            $content2 = Get-Content $filePath -Raw
            $content2 | Should -Match 'sops:'
            $content2 | Should -Match 'ENC\['

            # Verify decryption still works
            $retrieved = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
            # Should return raw YAML string
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
            # Rapid operations
            Set-Secret -Name $secretName -Secret 'v1' -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v2' -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v3' -Vault $script:ScenarioVaultName
            Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName
            Set-Secret -Name $secretName -Secret 'v4' -Vault $script:ScenarioVaultName

            # Final state should be v4
            $retrieved = Get-Secret -Name $secretName -Vault $script:ScenarioVaultName -AsPlainText
            # Should return raw YAML string
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'value:\s*v4'

        }
 finally {
            Remove-Secret -Name $secretName -Vault $script:ScenarioVaultName -ErrorAction SilentlyContinue
        }
    }
}
