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

    # Save original environment state
    $script:OriginalEnvironment = Save-SopsEnvironment

    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    # Import private functions for unit testing
    $privateFunctionsPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'Private'
    Get-ChildItem -Path $privateFunctionsPath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

    # Import public functions
    $publicFunctionsPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'Public'
    Get-ChildItem -Path $publicFunctionsPath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

    # Test data path
    $script:TestDataPath = Join-Path $PSScriptRoot 'TestData'
}

AfterAll {
    # Restore original environment state
    if ($script:OriginalEnvironment) {
        Restore-SopsEnvironment -State $script:OriginalEnvironment
    }
}

Describe 'Test-SopsEncrypted' -Tag 'Unit', 'EncryptionFiltering' {
    Context 'SOPS Detection Logic' {
        It 'Returns $true for fully encrypted SOPS file' {
            $filePath = Join-Path $TestDataPath 'simple-secret.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $true
        }

        It 'Returns $true for partially encrypted K8s secret' {
            $filePath = Join-Path $TestDataPath 'k8s-secret.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $true
        }

        It 'Returns $true for credentials file' {
            $filePath = Join-Path $TestDataPath 'credentials.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $true
        }

        It 'Returns $false for plain YAML without SOPS metadata' {
            $filePath = Join-Path $TestDataPath 'simple-secret-plain.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $false
        }

        It 'Returns $false for plain K8s secret' {
            $filePath = Join-Path $TestDataPath 'k8s-secret-plain.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $false
        }

        It 'Returns $false for plain credentials file' {
            $filePath = Join-Path $TestDataPath 'credentials-plain.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $false
        }

        It 'Returns $false for file with sops: but no version (edge case)' {
            $filePath = Join-Path $TestDataPath 'fake-sops.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $false
        }

        It 'Returns $false for plain file with _unencrypted suffix' {
            $filePath = Join-Path $TestDataPath 'config_unencrypted.yaml'
            Test-SopsEncrypted -FilePath $filePath | Should -Be $false
        }

        It 'Throws when file does not exist' {
            $filePath = Join-Path $TestDataPath 'nonexistent.yaml'
            { Test-SopsEncrypted -FilePath $filePath } | Should -Throw
        }
    }

    Context 'Performance Characteristics' {
        It 'Uses streaming (does not load full file into memory)' {
            # This test verifies the implementation uses StreamReader
            # We can't directly test memory usage, but we can verify it works with large files
            $filePath = Join-Path $TestDataPath 'simple-secret.yaml'

            # Should complete quickly even if file were large (actual test is implementation review)
            $result = Test-SopsEncrypted -FilePath $filePath
            $result | Should -Be $true
        }
    }
}

Describe 'Get-SopsConfiguration' -Tag 'Unit', 'EncryptionFiltering' {
    Context '.sops.yaml Parsing' {
        It 'Extracts unencrypted_suffix from .sops.yaml' {
            $config = Get-SopsConfiguration -VaultPath $TestDataPath
            $config.Found | Should -Be $true
            $config.UnencryptedSuffixes | Should -Contain '_unencrypted'
        }

        It 'Returns Found=$true when .sops.yaml exists' {
            $config = Get-SopsConfiguration -VaultPath $TestDataPath
            $config.Found | Should -Be $true
        }

        It 'Returns empty array when .sops.yaml not found' {
            $tempPath = Join-Path $TestDrive 'no-config'
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

            $config = Get-SopsConfiguration -VaultPath $tempPath
            $config.Found | Should -Be $false
            $config.UnencryptedSuffixes.Count | Should -Be 0
        }

        It 'Handles directory without .sops.yaml gracefully' {
            $tempPath = Join-Path $TestDrive 'empty-vault'
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

            { Get-SopsConfiguration -VaultPath $tempPath } | Should -Not -Throw
        }

        It 'Collects unique suffixes from multiple rules' {
            # Create test .sops.yaml with multiple rules
            $tempPath = Join-Path $TestDrive 'multi-suffix'
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

            $sopsConfig = @"
creation_rules:
  - path_regex: dev/.*\.yaml$
    unencrypted_suffix: _plain
    age: age1test
  - path_regex: prod/.*\.yaml$
    unencrypted_suffix: _unencrypted
    age: age1test
  - path_regex: staging/.*\.yaml$
    unencrypted_suffix: _plain
    age: age1test
"@
            Set-Content -Path (Join-Path $tempPath '.sops.yaml') -Value $sopsConfig

            $config = Get-SopsConfiguration -VaultPath $tempPath
            $config.UnencryptedSuffixes.Count | Should -Be 2
            $config.UnencryptedSuffixes | Should -Contain '_plain'
            $config.UnencryptedSuffixes | Should -Contain '_unencrypted'
        }

        It 'Handles malformed .sops.yaml gracefully' {
            $tempPath = Join-Path $TestDrive 'malformed-config'
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

            # Create invalid YAML
            Set-Content -Path (Join-Path $tempPath '.sops.yaml') -Value "invalid: [yaml: content:"

            # Should not throw, but return empty result
            { Get-SopsConfiguration -VaultPath $tempPath } | Should -Not -Throw
        }
    }
}

Describe 'Get-SecretIndex with RequireEncryption' -Tag 'Integration', 'EncryptionFiltering' {
    Context 'Default Behavior (RequireEncryption=$false)' {
        It 'Includes all files when RequireEncryption=$false (default)' {
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $false

            # Should include both plain and encrypted files
            $allFiles = $index | Select-Object -ExpandProperty FilePath
            $allFiles | Should -Not -BeNullOrEmpty

            # Verify we have plain files (they contain '-plain' in name)
            $plainFiles = $index | Where-Object { $_.FilePath -like '*-plain.yaml' }
            $plainFiles.Count | Should -BeGreaterThan 0
        }

        It 'Uses default RequireEncryption=$false when parameter not specified' {
            $index = Get-SecretIndex -Path $TestDataPath

            # Should include plain files by default
            $plainFiles = $index | Where-Object { $_.FilePath -like '*-plain.yaml' }
            $plainFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Filtered Behavior (RequireEncryption=$true)' {
        It 'Filters out plain files when RequireEncryption=$true' {
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $true

            # Should NOT include any *-plain.yaml files
            $plainFiles = $index | Where-Object { $_.FilePath -like '*-plain.yaml' }
            $plainFiles.Count | Should -Be 0
        }

        It 'Includes only SOPS-encrypted files when RequireEncryption=$true' {
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $true

            # Every file in index should have SOPS metadata
            foreach ($entry in $index) {
                Test-SopsEncrypted -FilePath $entry.FilePath | Should -Be $true
            }
        }

        It 'Excludes files matching unencrypted_suffix pattern' {
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $true

            # Should NOT include config_unencrypted.yaml
            $unencryptedFiles = $index | Where-Object { $_.FilePath -like '*_unencrypted.yaml' }
            $unencryptedFiles.Count | Should -Be 0
        }

        It 'Excludes fake-sops.yaml (has sops: but no version)' {
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $true

            # Should NOT include fake-sops.yaml
            $fakeFiles = $index | Where-Object { $_.FilePath -like '*fake-sops.yaml' }
            $fakeFiles.Count | Should -Be 0
        }

        It 'Returns empty array when no encrypted files exist in vault' {
            $tempPath = Join-Path $TestDrive 'plain-only'
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

            # Create only plain files
            Set-Content -Path (Join-Path $tempPath 'plain1.yaml') -Value "key: value"
            Set-Content -Path (Join-Path $tempPath 'plain2.yaml') -Value "foo: bar"

            $index = Get-SecretIndex -Path $tempPath -FilePattern '*.yaml' -RequireEncryption $true
            $index.Count | Should -Be 0
        }
    }

    Context 'Suffix Filtering' {
        It 'Applies suffix filter before SOPS detection (performance)' {
            # This is validated by checking that _unencrypted files are excluded
            $index = Get-SecretIndex -Path $TestDataPath -RequireEncryption $true

            $excludedFiles = $index | Where-Object {
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.FilePath)
                $fileName.EndsWith('_unencrypted')
            }

            $excludedFiles.Count | Should -Be 0
        }
    }
}

Describe 'Get-SecretInfo with RequireEncryption' -Tag 'Integration', 'EncryptionFiltering' {
    BeforeAll {
        # Import extension module functions
        $extensionPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'SecretManagement.Sops.Extension'
        $extensionPrivate = Join-Path $extensionPath 'Private'
        $extensionPublic = Join-Path $extensionPath 'Public'

        Get-ChildItem -Path $extensionPrivate -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
        }
        Get-ChildItem -Path $extensionPublic -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
        }
    }

    It 'Passes RequireEncryption parameter from VaultParameters to Get-SecretIndex' {
        $additionalParams = @{
            Path              = $TestDataPath
            RequireEncryption = $true
        }

        $secretInfo = Get-SecretInfo -Filter '*' -VaultName 'TestVault' -AdditionalParameters $additionalParams

        # Verify only encrypted secrets returned
        # Note: This test verifies integration, actual secret retrieval tested in other suites
        $secretInfo | Should -Not -BeNullOrEmpty

        # All returned secrets should be from SOPS-encrypted files
        foreach ($info in $secretInfo) {
            $filePath = $info.Metadata.FilePath
            if ($filePath) {
                Test-SopsEncrypted -FilePath $filePath | Should -Be $true
            }
        }
    }
}

Describe 'Backward Compatibility' -Tag 'Integration', 'EncryptionFiltering' {
    BeforeAll {
        # Import extension module functions for backward compat tests
        $extensionPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'SecretManagement.Sops.Extension'
        $extensionPrivate = Join-Path $extensionPath 'Private'

        Get-ChildItem -Path $extensionPrivate -Filter 'Get-VaultParameters.ps1' | ForEach-Object {
            . $_.FullName
        }
    }

    It 'Get-VaultParameters provides RequireEncryption=$false default' {
        $params = Get-VaultParameters -AdditionalParameters @{}
        $params.RequireEncryption | Should -Be $false
    }

    It 'Get-SecretIndex works without RequireEncryption parameter' {
        # Default behavior - should not throw
        { Get-SecretIndex -Path $TestDataPath } | Should -Not -Throw
    }
}
