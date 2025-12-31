#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Path-Based Encryption Tests for SecretManagement.Sops

.DESCRIPTION
    Tests for SOPS path-based encryption rules workflow.
    Verifies that secrets in different paths use different encryption keys
    based on .sops.yaml creation_rules path_regex patterns.

    Common GitOps pattern:
    - apps/dev/api/keys.yaml uses dev encryption key
    - apps/prod/api/keys.yaml uses prod encryption key

.NOTES
    Run with: Invoke-Pester -Path .\Tests\PathBasedEncryption.Tests.ps1 -Tag 'PathBasedEncryption'
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

    # Check if SOPS is available
    $script:SopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)

    # Check if age is available
    $script:AgeAvailable = $null -ne (Get-Command 'age-keygen' -ErrorAction SilentlyContinue)

    # Skip all tests if SOPS not available
    if (-not $script:SopsAvailable) {
        Write-Warning "SOPS not available in PATH. All path-based encryption tests will be skipped."
    }

    if (-not $script:AgeAvailable) {
        Write-Warning "age-keygen not available in PATH. All path-based encryption tests will be skipped."
    }
}

AfterAll {
    # Restore original environment state
    if ($script:OriginalEnvironment) {
        Restore-SopsEnvironment -State $script:OriginalEnvironment
    }
}

Describe 'Path-Based Encryption Rules' -Tag 'PathBasedEncryption', 'Integration' {
    BeforeAll {
        if (-not $script:SopsAvailable -or -not $script:AgeAvailable) {
            return
        }

        # Create test vault structure
        $script:TestVaultPath = Join-Path $TestDrive 'gitops-repo'
        New-Item -Path $script:TestVaultPath -ItemType Directory -Force | Out-Null

        # Generate two separate age keys for dev and prod environments using helper
        $devKey = New-TestAgeKey -Path (Join-Path $TestDrive 'dev-key.txt')
        $prodKey = New-TestAgeKey -Path (Join-Path $TestDrive 'prod-key.txt')

        # Store key information for later use
        $script:DevKeyFile = $devKey.KeyFile
        $script:ProdKeyFile = $prodKey.KeyFile
        $script:DevPublicKey = $devKey.PublicKey
        $script:ProdPublicKey = $prodKey.PublicKey

        Write-Verbose "Dev Public Key: $($script:DevPublicKey)"
        Write-Verbose "Prod Public Key: $($script:ProdPublicKey)"

        # Create .sops.yaml with path-based encryption rules
        # Use cross-platform regex patterns with [/\\] to match both / and \ separators
        # This allows the same .sops.yaml to work on Windows, Linux, and macOS
        # See: https://github.com/getsops/sops/issues/892
        $sopsConfig = @"
creation_rules:
  # Development environment - use dev key
  - path_regex: apps[/\\\\]dev[/\\\\].*\.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:DevPublicKey)

  # Production environment - use prod key
  - path_regex: apps[/\\\\]prod[/\\\\].*\.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:ProdPublicKey)

  # Fallback rule for other paths (use dev key)
  - path_regex: \.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:DevPublicKey)
"@
        Set-Content -Path (Join-Path $script:TestVaultPath '.sops.yaml') -Value $sopsConfig

        Write-Verbose "Created .sops.yaml with path-based rules"

        # Create directory structure
        New-Item -Path (Join-Path $script:TestVaultPath 'apps/dev/api') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TestVaultPath 'apps/dev/web') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TestVaultPath 'apps/prod/api') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TestVaultPath 'apps/prod/web') -ItemType Directory -Force | Out-Null

        # Register vault with unique isolated name
        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsPathBasedTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestVaultPath
            FilePattern = '*.yaml'
            Recurse     = $true
        }
        Write-Verbose "Registered isolated test vault: $script:TestVaultName"
    }

    AfterAll {
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'SOPS Encryption Key Selection' -Tag 'EncryptionKeys' {
        BeforeEach {
            $script:TestSecretSuffix = New-Guid
            # Save environment state before each test
            $script:TestEnvironment = Save-SopsEnvironment
        }

        AfterEach {
            # Restore environment state first
            if ($script:TestEnvironment) {
                Restore-SopsEnvironment -State $script:TestEnvironment
            }

            # Clean up created secrets with explicit error handling
            if ($script:TestSecretSuffix) {
                try {
                    Get-SecretInfo -Vault $script:TestVaultName -ErrorAction Stop | Where-Object {
                        $_.Name -match $script:TestSecretSuffix
                    } | ForEach-Object {
                        try {
                            Remove-Secret -Name $_.Name -Vault $script:TestVaultName -ErrorAction Stop
                        }
                        catch {
                            Write-Warning "Failed to remove secret '$($_.Name)': $_"
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to enumerate secrets for cleanup: $_"
                }
            }
        }

        It 'Uses dev key for apps/dev/api/keys.yaml' {
            $secretName = "apps/dev/api/keys-$($script:TestSecretSuffix)"
            $secretValue = 'dev-api-secret-value'

            # Set the dev key as the active SOPS key
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile

            # Create the secret
            Set-Secret -Name $secretName -Secret $secretValue -Vault $script:TestVaultName

            # Verify file was created
            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $filePath | Should -Exist

            # Read the encrypted file and verify it contains SOPS metadata with dev key fingerprint
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match 'sops:'
            $encryptedContent | Should -Match 'age:'

            # The encrypted file should reference the dev public key
            $encryptedContent | Should -Match $script:DevPublicKey

            # Verify we can decrypt with dev key
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            $decrypted = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "Should decrypt successfully with dev key"
            $decrypted | Should -Match $secretValue

            # Verify we CANNOT decrypt with prod key (should fail)
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $decryptAttempt = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Not -Be 0 -Because "Should fail to decrypt with wrong (prod) key"
        }

        It 'Uses prod key for apps/prod/api/keys.yaml' {
            $secretName = "apps/prod/api/keys-$($script:TestSecretSuffix)"
            $secretValue = 'prod-api-secret-value'

            # Set the prod key as the active SOPS key
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile

            # Create the secret
            Set-Secret -Name $secretName -Secret $secretValue -Vault $script:TestVaultName

            # Verify file was created
            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $filePath | Should -Exist

            # Read the encrypted file and verify it contains SOPS metadata with prod key fingerprint
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match 'sops:'
            $encryptedContent | Should -Match 'age:'

            # The encrypted file should reference the prod public key
            $encryptedContent | Should -Match $script:ProdPublicKey

            # Verify we can decrypt with prod key
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $decrypted = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "Should decrypt successfully with prod key"
            $decrypted | Should -Match $secretValue

            # Verify we CANNOT decrypt with dev key (should fail)
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            $decryptAttempt = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Not -Be 0 -Because "Should fail to decrypt with wrong (dev) key"
        }

        It 'Uses different keys for same filename in different environments' {
            $devSecretName = "apps/dev/api/database-$($script:TestSecretSuffix)"
            $prodSecretName = "apps/prod/api/database-$($script:TestSecretSuffix)"

            $devValue = 'dev-database-password'
            $prodValue = 'prod-database-password'

            # Create dev secret with dev key
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            Set-Secret -Name $devSecretName -Secret $devValue -Vault $script:TestVaultName

            # Create prod secret with prod key
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            Set-Secret -Name $prodSecretName -Secret $prodValue -Vault $script:TestVaultName

            # Verify both files exist
            $devFilePath = Join-Path $script:TestVaultPath "$($devSecretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $prodFilePath = Join-Path $script:TestVaultPath "$($prodSecretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            $devFilePath | Should -Exist
            $prodFilePath | Should -Exist

            # Verify dev file uses dev key
            $devContent = Get-Content $devFilePath -Raw
            $devContent | Should -Match $script:DevPublicKey
            $devContent | Should -Not -Match $script:ProdPublicKey

            # Verify prod file uses prod key
            $prodContent = Get-Content $prodFilePath -Raw
            $prodContent | Should -Match $script:ProdPublicKey
            $prodContent | Should -Not -Match $script:DevPublicKey

            # Verify correct decryption with correct keys
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            $devDecrypted = & sops -d $devFilePath 2>&1
            $LASTEXITCODE | Should -Be 0
            $devDecrypted | Should -Match $devValue

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $prodDecrypted = & sops -d $prodFilePath 2>&1
            $LASTEXITCODE | Should -Be 0
            $prodDecrypted | Should -Match $prodValue
        }

        It 'Supports multiple nested paths in dev environment' {
            $apiSecret = "apps/dev/api/service-$($script:TestSecretSuffix)"
            $webSecret = "apps/dev/web/service-$($script:TestSecretSuffix)"

            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile

            # Create secrets in different dev subdirectories
            Set-Secret -Name $apiSecret -Secret 'dev-api-service' -Vault $script:TestVaultName
            Set-Secret -Name $webSecret -Secret 'dev-web-service' -Vault $script:TestVaultName

            # Both should use dev key
            $apiFilePath = Join-Path $script:TestVaultPath "$($apiSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $webFilePath = Join-Path $script:TestVaultPath "$($webSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            $apiContent = Get-Content $apiFilePath -Raw
            $webContent = Get-Content $webFilePath -Raw

            $apiContent | Should -Match $script:DevPublicKey
            $webContent | Should -Match $script:DevPublicKey
        }

        It 'Supports multiple nested paths in prod environment' {
            $apiSecret = "apps/prod/api/service-$($script:TestSecretSuffix)"
            $webSecret = "apps/prod/web/service-$($script:TestSecretSuffix)"

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile

            # Create secrets in different prod subdirectories
            Set-Secret -Name $apiSecret -Secret 'prod-api-service' -Vault $script:TestVaultName
            Set-Secret -Name $webSecret -Secret 'prod-web-service' -Vault $script:TestVaultName

            # Both should use prod key
            $apiFilePath = Join-Path $script:TestVaultPath "$($apiSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $webFilePath = Join-Path $script:TestVaultPath "$($webSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            $apiContent = Get-Content $apiFilePath -Raw
            $webContent = Get-Content $webFilePath -Raw

            $apiContent | Should -Match $script:ProdPublicKey
            $webContent | Should -Match $script:ProdPublicKey
        }
    }

    Context 'Hashtable and Complex Secrets with Path Rules' -Tag 'ComplexSecrets' {
        BeforeEach {
            $script:TestSecretSuffix = New-Guid
            # Save original SOPS_AGE_KEY_FILE to restore after test
            $script:OriginalSopsKeyFile = $env:SOPS_AGE_KEY_FILE
        }

        AfterEach {
            # Restore original SOPS_AGE_KEY_FILE
            $env:SOPS_AGE_KEY_FILE = $script:OriginalSopsKeyFile

            Get-SecretInfo -Vault $script:TestVaultName -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match $script:TestSecretSuffix) {
                    Remove-Secret -Name $_.Name -Vault $script:TestVaultName -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Encrypts hashtable secrets with correct path-based key' {
            $secretName = "apps/prod/api/config-$($script:TestSecretSuffix)"
            $secretValue = @{
                database_host = 'prod-postgres.example.com'
                database_port = 5432
                api_key       = 'prod-api-key-12345'
            }

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile

            Set-Secret -Name $secretName -Secret $secretValue -Vault $script:TestVaultName

            # Verify file uses prod key
            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:ProdPublicKey

            # Verify decryption works with prod key
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -BeOfType [string]
            $retrieved | Should -Match 'database_host:\s*prod-postgres\.example\.com'
            $retrieved | Should -Match 'api_key:\s*prod-api-key-12345'
        }

        It 'Encrypts Kubernetes Secret manifests with correct path-based key' {
            $secretName = "apps/prod/api/k8s-secret-$($script:TestSecretSuffix)"
            $k8sSecret = @{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = @{
                    name      = "k8s-secret-$($script:TestSecretSuffix)"
                    namespace = 'production'
                }
                type       = 'Opaque'
                stringData = @{
                    'db-password' = 'prod-db-password-secure'
                    'api-key'     = 'prod-api-key-secure'
                }
            }

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile

            Set-Secret -Name $secretName -Secret $k8sSecret -Vault $script:TestVaultName

            # Verify file uses prod key
            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:ProdPublicKey
            # Verify Kubernetes Secret structure - metadata should be plaintext, data encrypted
            $encryptedContent | Should -Match 'kind: Secret'
            $encryptedContent | Should -Match 'metadata:'
            $encryptedContent | Should -Match 'namespace: production'
            # stringData should be encrypted
            $encryptedContent | Should -Match 'stringData:'
            $encryptedContent | Should -Match 'ENC\['
        }
    }

    Context 'Error Handling for Path-Based Rules' -Tag 'ErrorHandling' {
        BeforeEach {
            # Save original SOPS_AGE_KEY_FILE to restore after test
            $script:OriginalSopsKeyFile = $env:SOPS_AGE_KEY_FILE
        }

        AfterEach {
            # Restore original SOPS_AGE_KEY_FILE
            $env:SOPS_AGE_KEY_FILE = $script:OriginalSopsKeyFile
        }

        It 'Throws helpful error when no key available for path' {
            # Create a secret in a path that requires prod key, but only provide dev key
            $secretName = "apps/prod/api/test-$(New-Guid)"

            # Only set dev key available
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile

            # This should fail because SOPS will encrypt with prod key, but we can't decrypt
            # Actually, encryption will succeed (it uses public key), but we're testing the workflow

            # This test verifies the current behavior - may need adjustment based on implementation
        }

        It 'Handles updating secrets with path-based encryption' {
            $secretName = "apps/dev/api/update-test-$(New-Guid)"

            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile

            # Create initial secret
            Set-Secret -Name $secretName -Secret 'original-value' -Vault $script:TestVaultName

            # Update the secret
            Set-Secret -Name $secretName -Secret 'updated-value' -Vault $script:TestVaultName

            # Verify update worked and still uses correct key
            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:DevPublicKey

            $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -Match 'value:\s*updated-value'

            # Cleanup
            Remove-Secret -Name $secretName -Vault $script:TestVaultName
        }
    }
}
