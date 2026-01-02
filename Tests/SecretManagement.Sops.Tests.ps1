#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import test helpers for isolation utilities
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    # Clean up any orphaned test vaults from previous runs
    Remove-OrphanedTestVaults

    # Save original environment state
    $script:OriginalEnvironment = Save-SopsEnvironment

    # Remove any existing module instances to prevent InModuleScope conflicts
    Get-Module 'SecretManagement.Sops' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import the main module
    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    # Test data directory
    $script:TestDataPath = Join-Path $PSScriptRoot 'TestData'

    # Configure test-specific age key in isolated environment
    $testKeyFile = Join-Path $script:TestDataPath 'test-key.txt'
    if (Test-Path $testKeyFile) {
        $env:SOPS_AGE_KEY_FILE = $testKeyFile
        Write-Verbose "Configured test-isolated SOPS_AGE_KEY_FILE: $testKeyFile"
    }
    else {
        Write-Warning "Test key file not found: $testKeyFile. Some tests may fail."
    }
}

AfterAll {
    # Restore original environment state
    if ($script:OriginalEnvironment) {
        Restore-SopsEnvironment -State $script:OriginalEnvironment
    }
}

Describe 'Module Import' -Tag 'ReadSupport', 'Unit' {
    It 'Main module manifest is valid' {
        $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
        { Test-ModuleManifest -Path $modulePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Extension module manifest is valid' {
        $extensionPath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.Extension\SecretManagement.Sops.Extension.psd1'
        { Test-ModuleManifest -Path $extensionPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Helper functions are available' {
        $expectedFunctions = @(
            'Test-SopsAvailable'
            'Invoke-SopsDecrypt'
            'Resolve-SecretName'
            'Get-SecretIndexEntry'
            'Get-SecretIndex'
        )

        foreach ($func in $expectedFunctions) {
            Get-Command $func -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "$func should be exported"
        }
    }
}

Describe 'Test-SopsAvailable' -Tag 'ReadSupport', 'Unit' {
    It 'Returns true when SOPS is in PATH' {
        Test-SopsAvailable | Should -Be $true
    }
}

Describe 'Resolve-SecretName' -Tag 'ReadSupport', 'Unit' {
    Context 'RelativePath strategy' {
        It 'Removes base path and extension' {
            $basePath = Join-Path $TestDrive 'secrets'
            $filePath = Join-Path $basePath 'db' 'password.yaml'
            $result = Resolve-SecretName -FilePath $filePath -BasePath $basePath -NamingStrategy 'RelativePath'
            $result | Should -Be 'db/password'
        }

        It 'Handles deeply nested paths' {
            $basePath = Join-Path $TestDrive 'secrets'
            $filePath = Join-Path $basePath 'app' 'prod' 'api' 'keys.yaml'
            $result = Resolve-SecretName -FilePath $filePath -BasePath $basePath -NamingStrategy 'RelativePath'
            $result | Should -Be 'app/prod/api/keys'
        }

        It 'Handles file in root of base path' {
            $basePath = Join-Path $TestDrive 'secrets'
            $filePath = Join-Path $basePath 'secret.yaml'
            $result = Resolve-SecretName -FilePath $filePath -BasePath $basePath -NamingStrategy 'RelativePath'
            $result | Should -Be 'secret'
        }
    }

    Context 'FileName strategy' {
        It 'Returns only filename without extension' {
            $basePath = Join-Path $TestDrive 'secrets'
            $filePath = Join-Path $basePath 'nested' 'deep' 'myfile.yaml'
            $result = Resolve-SecretName -FilePath $filePath -BasePath $basePath -NamingStrategy 'FileName'
            $result | Should -Be 'myfile'
        }
    }
}

Describe 'Integration Tests' -Tag 'ReadSupport', 'Integration', 'RequiresSops' {
    BeforeAll {
        # Store test key file path for vault registration
        $testKeyFile = Join-Path $script:TestDataPath 'test-key.txt'
        if (-not (Test-Path $testKeyFile)) {
            Write-Warning "Test key file not found: $testKeyFile. Some tests may fail."
        }
    }

    Context 'Invoke-SopsDecrypt' {
        It 'Decrypts simple YAML file' {
            $testFile = Join-Path $script:TestDataPath 'simple-secret.yaml'
            $result = Invoke-SopsDecrypt -FilePath $testFile
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match 'database_host'
        }

        It 'Throws on non-existent file' {
            { Invoke-SopsDecrypt -FilePath 'C:\nonexistent.yaml' } | Should -Throw
        }
    }

    Context 'Get-SecretIndex' {
        It 'Finds YAML files in directory' {
            $index = Get-SecretIndex -Path $script:TestDataPath -FilePattern '*.yaml' -Recurse $false
            $index | Should -Not -BeNullOrEmpty
            $index.Count | Should -BeGreaterThan 0
        }

        It 'Indexes Kubernetes Secret YAML files' {
            $index = Get-SecretIndex -Path $script:TestDataPath -FilePattern 'k8s-secret.yaml' -Recurse $false
            # Since we return raw YAML, the index uses the filename, not K8s metadata.name
            $k8sEntry = $index | Where-Object { $_.Name -match 'k8s-secret' } | Select-Object -First 1
            $k8sEntry | Should -Not -BeNullOrEmpty
            $k8sEntry.Name | Should -Be 'k8s-secret'
        }
    }

    Context 'SecretManagement Extension' {
        BeforeAll {
            # Import SecretManagement module
            Import-Module Microsoft.PowerShell.SecretManagement -Force

            # Configure test environment with AGE key
            $env:SOPS_AGE_KEY_FILE = $testKeyFile

            # Register test vault with unique isolated name
            $modulePath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops'
            $script:VaultName = New-IsolatedTestVault -BaseName 'SopsMainTest' -ModulePath $modulePath -VaultParameters @{
                Path        = $script:TestDataPath
                FilePattern = '*.yaml'
                Recurse     = $false
                AgeKeyFile  = $testKeyFile
            }
            Write-Verbose "Registered isolated test vault: $script:VaultName"
        }

        AfterAll {
            if ($script:VaultName) {
                Remove-IsolatedTestVault -VaultName $script:VaultName
            }
        }

        It 'Test-SecretVault returns true for valid configuration' {
            Test-SecretVault -Name $script:VaultName | Should -Be $true
        }

        It 'Get-SecretInfo lists available secrets' {
            $secrets = Get-SecretInfo -Vault $script:VaultName
            $secrets | Should -Not -BeNullOrEmpty
            $secrets.Count | Should -BeGreaterThan 0
        }

        It 'Get-SecretInfo filters by pattern' {
            $secrets = Get-SecretInfo -Vault $script:VaultName -Name 'api*'
            $secrets | Should -Not -BeNullOrEmpty
            $secrets.Name | Should -Match 'api'
        }

        It 'Get-Secret retrieves simple secret' {
            # This will depend on the actual secret names in your test data
            $secrets = Get-SecretInfo -Vault $script:VaultName
            $firstSecret = $secrets | Select-Object -First 1

            if ($firstSecret) {
                $secret = Get-Secret -Name $firstSecret.Name -Vault $script:VaultName -AsPlainText
                $secret | Should -Not -BeNullOrEmpty
            }
        }

        It 'Get-Secret retrieves K8s Secret as raw YAML' {
            $secret = Get-Secret -Name 'k8s-secret' -Vault $script:VaultName -AsPlainText
            # Should return raw YAML string, not typed object
            $secret | Should -BeOfType [string]
            $secret | Should -Match 'license-key'
            $secret | Should -Match 'software-license'
        }

        It 'Get-Secret returns raw YAML for username/password' {
            # Find the credentials secret
            $secrets = Get-SecretInfo -Vault $script:VaultName
            $credSecret = $secrets | Where-Object { $_.Name -match 'credentials' } | Select-Object -First 1

            if ($credSecret) {
                $cred = Get-Secret -Name $credSecret.Name -Vault $script:VaultName -AsPlainText
                # Should return raw YAML string, not PSCredential
                $cred | Should -BeOfType [string]
                $cred | Should -Match 'username'
                $cred | Should -Match 'password'
            }
        }

        It 'Get-Secret returns null for non-existent secret' {
            $secret = Get-Secret -Name 'nonexistent-secret' -Vault $script:VaultName -ErrorAction SilentlyContinue
            $secret | Should -BeNullOrEmpty
        }
    }
}

Describe 'Error Handling' -Tag 'ReadSupport', 'Unit' {
    It 'Provides helpful error for missing SOPS binary' {
        InModuleScope 'SecretManagement.Sops' {
            Mock Test-SopsAvailable { return $false }

            $testFile = Join-Path $TestDrive 'test.yaml'
            Set-Content -Path $testFile -Value 'key: value'

            { Invoke-SopsDecrypt -FilePath $testFile } | Should -Throw '*SOPS binary not found*'
        }
    }

    It 'Provides helpful error for Azure CLI issues' {
        Mock Test-SopsAvailable { $true } -ModuleName 'SecretManagement.Sops'
        Mock Invoke-Expression {
            $global:LASTEXITCODE = 1
            return "az: command not found"
        } -ModuleName 'SecretManagement.Sops'

        # This test would need more sophisticated mocking to work properly
        # Left as a placeholder for future enhancement
    }
}
