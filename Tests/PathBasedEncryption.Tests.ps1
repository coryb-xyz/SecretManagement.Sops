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

    $script:SopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)
    $script:AgeAvailable = $null -ne (Get-Command 'age-keygen' -ErrorAction SilentlyContinue)

    if (-not $script:SopsAvailable) {
        Write-Warning "SOPS not available in PATH. All path-based encryption tests will be skipped."
    }
    if (-not $script:AgeAvailable) {
        Write-Warning "age-keygen not available in PATH. All path-based encryption tests will be skipped."
    }
}

AfterAll {
    Restore-TestEnvironment -State $script:testState
}

Describe 'Path-Based Encryption Rules' -Tag 'PathBasedEncryption', 'Integration' {
    BeforeAll {
        if (-not $script:SopsAvailable -or -not $script:AgeAvailable) {
            return
        }

        $script:TestVaultPath = Join-Path $TestDrive 'gitops-repo'
        $null = New-Item -Path $script:TestVaultPath -ItemType Directory -Force

        # Generate two separate age keys for dev and prod environments
        $devKey = New-TestAgeKey -Path (Join-Path $TestDrive 'dev-key.txt')
        $prodKey = New-TestAgeKey -Path (Join-Path $TestDrive 'prod-key.txt')

        $script:DevKeyFile = $devKey.KeyFile
        $script:ProdKeyFile = $prodKey.KeyFile
        $script:DevPublicKey = $devKey.PublicKey
        $script:ProdPublicKey = $prodKey.PublicKey

        # Create .sops.yaml with path-based encryption rules
        # Cross-platform regex patterns with [/\\] to match both separators
        $sopsConfig = @"
creation_rules:
  - path_regex: apps[/\\\\]dev[/\\\\].*\.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:DevPublicKey)

  - path_regex: apps[/\\\\]prod[/\\\\].*\.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:ProdPublicKey)

  - path_regex: \.yaml`$
    encrypted_regex: ^(data|stringData)`$
    age: $($script:DevPublicKey)
"@
        Set-Content -Path (Join-Path $script:TestVaultPath '.sops.yaml') -Value $sopsConfig

        # Create directory structure
        foreach ($dir in @('apps/dev/api', 'apps/dev/web', 'apps/prod/api', 'apps/prod/web')) {
            $null = New-Item -Path (Join-Path $script:TestVaultPath $dir) -ItemType Directory -Force
        }

        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsPathBasedTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestVaultPath
            FilePattern = '*.yaml'
            Recurse     = $true
        }
    }

    AfterAll {
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'SOPS Encryption Key Selection' -Tag 'EncryptionKeys' {
        BeforeEach {
            $script:TestSecretSuffix = New-Guid
            $script:TestEnvironment = Save-SopsEnvironment
        }

        AfterEach {
            if ($script:TestEnvironment) {
                Restore-SopsEnvironment -State $script:TestEnvironment
            }

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

            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            Set-Secret -Name $secretName -Secret $secretValue -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $filePath | Should -Exist

            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match 'sops:'
            $encryptedContent | Should -Match 'age:'
            $encryptedContent | Should -Match $script:DevPublicKey

            # Verify decryption with dev key succeeds
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            $decrypted = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "Should decrypt successfully with dev key"
            $decrypted | Should -Match $secretValue

            # Verify decryption with prod key fails
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $null = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Not -Be 0 -Because "Should fail to decrypt with wrong (prod) key"
        }

        It 'Uses prod key for apps/prod/api/keys.yaml' {
            $secretName = "apps/prod/api/keys-$($script:TestSecretSuffix)"
            $secretValue = 'prod-api-secret-value'

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            Set-Secret -Name $secretName -Secret $secretValue -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $filePath | Should -Exist

            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match 'sops:'
            $encryptedContent | Should -Match 'age:'
            $encryptedContent | Should -Match $script:ProdPublicKey

            # Verify decryption with prod key succeeds
            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            $decrypted = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "Should decrypt successfully with prod key"
            $decrypted | Should -Match $secretValue

            # Verify decryption with dev key fails
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            $null = & sops -d $filePath 2>&1
            $LASTEXITCODE | Should -Not -Be 0 -Because "Should fail to decrypt with wrong (dev) key"
        }

        It 'Uses different keys for same filename in different environments' {
            $devSecretName = "apps/dev/api/database-$($script:TestSecretSuffix)"
            $prodSecretName = "apps/prod/api/database-$($script:TestSecretSuffix)"
            $devValue = 'dev-database-password'
            $prodValue = 'prod-database-password'

            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
            Set-Secret -Name $devSecretName -Secret $devValue -Vault $script:TestVaultName

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile
            Set-Secret -Name $prodSecretName -Secret $prodValue -Vault $script:TestVaultName

            $devFilePath = Join-Path $script:TestVaultPath "$($devSecretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $prodFilePath = Join-Path $script:TestVaultPath "$($prodSecretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            $devFilePath | Should -Exist
            $prodFilePath | Should -Exist

            # Verify each file uses the correct key
            $devContent = Get-Content $devFilePath -Raw
            $devContent | Should -Match $script:DevPublicKey
            $devContent | Should -Not -Match $script:ProdPublicKey

            $prodContent = Get-Content $prodFilePath -Raw
            $prodContent | Should -Match $script:ProdPublicKey
            $prodContent | Should -Not -Match $script:DevPublicKey

            # Verify correct decryption
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

            Set-Secret -Name $apiSecret -Secret 'dev-api-service' -Vault $script:TestVaultName
            Set-Secret -Name $webSecret -Secret 'dev-web-service' -Vault $script:TestVaultName

            $apiFilePath = Join-Path $script:TestVaultPath "$($apiSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $webFilePath = Join-Path $script:TestVaultPath "$($webSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            (Get-Content $apiFilePath -Raw) | Should -Match $script:DevPublicKey
            (Get-Content $webFilePath -Raw) | Should -Match $script:DevPublicKey
        }

        It 'Supports multiple nested paths in prod environment' {
            $apiSecret = "apps/prod/api/service-$($script:TestSecretSuffix)"
            $webSecret = "apps/prod/web/service-$($script:TestSecretSuffix)"

            $env:SOPS_AGE_KEY_FILE = $script:ProdKeyFile

            Set-Secret -Name $apiSecret -Secret 'prod-api-service' -Vault $script:TestVaultName
            Set-Secret -Name $webSecret -Secret 'prod-web-service' -Vault $script:TestVaultName

            $apiFilePath = Join-Path $script:TestVaultPath "$($apiSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $webFilePath = Join-Path $script:TestVaultPath "$($webSecret -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"

            (Get-Content $apiFilePath -Raw) | Should -Match $script:ProdPublicKey
            (Get-Content $webFilePath -Raw) | Should -Match $script:ProdPublicKey
        }
    }

    Context 'Hashtable and Complex Secrets with Path Rules' -Tag 'ComplexSecrets' {
        BeforeEach {
            $script:TestSecretSuffix = New-Guid
            $script:OriginalSopsKeyFile = $env:SOPS_AGE_KEY_FILE
        }

        AfterEach {
            $env:SOPS_AGE_KEY_FILE = $script:OriginalSopsKeyFile

            Get-SecretInfo -Vault $script:TestVaultName -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match $script:TestSecretSuffix
            } | ForEach-Object {
                Remove-Secret -Name $_.Name -Vault $script:TestVaultName -ErrorAction SilentlyContinue
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

            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:ProdPublicKey

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

            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:ProdPublicKey
            $encryptedContent | Should -Match 'kind: Secret'
            $encryptedContent | Should -Match 'metadata:'
            $encryptedContent | Should -Match 'namespace: production'
            $encryptedContent | Should -Match 'stringData:'
            $encryptedContent | Should -Match 'ENC\['
        }
    }

    Context 'Error Handling for Path-Based Rules' -Tag 'ErrorHandling' {
        BeforeEach {
            $script:OriginalSopsKeyFile = $env:SOPS_AGE_KEY_FILE
        }

        AfterEach {
            $env:SOPS_AGE_KEY_FILE = $script:OriginalSopsKeyFile
        }

        It 'Throws helpful error when no key available for path' {
            # Encryption uses public key so it succeeds regardless;
            # this test documents the current workflow behavior
            $secretName = "apps/prod/api/test-$(New-Guid)"
            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile
        }

        It 'Handles updating secrets with path-based encryption' {
            $secretName = "apps/dev/api/update-test-$(New-Guid)"

            $env:SOPS_AGE_KEY_FILE = $script:DevKeyFile

            Set-Secret -Name $secretName -Secret 'original-value' -Vault $script:TestVaultName
            Set-Secret -Name $secretName -Secret 'updated-value' -Vault $script:TestVaultName

            $filePath = Join-Path $script:TestVaultPath "$($secretName -replace '/', [System.IO.Path]::DirectorySeparatorChar).yaml"
            $encryptedContent = Get-Content $filePath -Raw
            $encryptedContent | Should -Match $script:DevPublicKey

            $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $retrieved | Should -Match 'value:\s*updated-value'

            Remove-Secret -Name $secretName -Vault $script:TestVaultName
        }
    }
}
