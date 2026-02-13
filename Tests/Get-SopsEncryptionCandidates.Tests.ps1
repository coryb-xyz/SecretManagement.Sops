BeforeAll {
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    $script:testState = Initialize-TestEnvironment

    # Dot-source required private functions
    $privatePath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'Private'
    foreach ($function in @('Get-SopsConfiguration.ps1', 'Test-PathMatchesRegex.ps1', 'Test-FileContainsKeys.ps1')) {
        $functionPath = Join-Path $privatePath $function
        if (Test-Path $functionPath) { . $functionPath }
    }

    # Dot-source the public function
    $publicFunctionPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'Public' 'Get-SopsEncryptionCandidates.ps1'
    if (Test-Path $publicFunctionPath) { . $publicFunctionPath }

    Import-Module powershell-yaml -ErrorAction Stop
}

AfterAll {
    Restore-TestEnvironment -State $script:testState
}

Describe 'Test-PathMatchesRegex' {
    Context 'Basic path matching' {
        It 'Matches Windows paths with backslashes' {
            $tempVault = Join-Path $TestDrive 'vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $tempVault 'migration') -ItemType Directory -Force
            $testFile = Join-Path $tempVault 'migration\k8s.yaml'

            Test-PathMatchesRegex -FilePath $testFile `
                -VaultPath $tempVault `
                -PathRegex 'migration[/\\].*\.yaml$' | Should -BeTrue
        }

        It 'Matches Unix-style paths with forward slashes' {
            $tempVault = Join-Path $TestDrive 'vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force

            Test-PathMatchesRegex -FilePath 'migration/k8s.yaml' `
                -VaultPath $tempVault `
                -PathRegex 'migration[/\\].*\.yaml$' | Should -BeTrue
        }

        It 'Uses relative path from vault root' {
            $tempVault = Join-Path $TestDrive 'vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $tempVault 'apps\web') -ItemType Directory -Force
            $testFile = Join-Path $tempVault 'apps\web\config.yaml'

            Test-PathMatchesRegex -FilePath $testFile `
                -VaultPath $tempVault `
                -PathRegex 'apps[/\\]web[/\\].*\.yaml$' | Should -BeTrue
        }

        It 'Returns false when path does not match regex' {
            $tempVault = Join-Path $TestDrive 'vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $testFile = Join-Path $tempVault 'other\file.yaml'

            Test-PathMatchesRegex -FilePath $testFile `
                -VaultPath $tempVault `
                -PathRegex 'migration[/\\].*\.yaml$' | Should -BeFalse
        }

        It 'Matches files at vault root with simple regex' {
            $tempVault = Join-Path $TestDrive 'vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $testFile = Join-Path $tempVault 'config.yaml'

            Test-PathMatchesRegex -FilePath $testFile `
                -VaultPath $tempVault `
                -PathRegex '\.yaml$' | Should -BeTrue
        }
    }
}

Describe 'Test-FileContainsKeys' {
    BeforeAll {
        $script:tempVault = Join-Path $TestDrive 'vault-keys'
        $null = New-Item -Path $script:tempVault -ItemType Directory -Force
    }

    Context 'K8s Secret key matching' {
        It 'Detects matching stringData key' {
            $k8sSecret = @"
apiVersion: v1
kind: Secret
metadata:
  name: test
stringData:
  password: secret123
"@
            $tempFile = Join-Path $script:tempVault 'k8s-secret.yaml'
            $k8sSecret | Out-File -FilePath $tempFile -Encoding utf8

            Test-FileContainsKeys -FilePath $tempFile `
                -EncryptedRegex '^(data|stringData)$' | Should -BeTrue
        }

        It 'Detects matching data key' {
            $k8sSecret = @"
apiVersion: v1
kind: Secret
metadata:
  name: test
data:
  password: c2VjcmV0MTIz
"@
            $tempFile = Join-Path $script:tempVault 'k8s-secret-data.yaml'
            $k8sSecret | Out-File -FilePath $tempFile -Encoding utf8

            Test-FileContainsKeys -FilePath $tempFile `
                -EncryptedRegex '^(data|stringData)$' | Should -BeTrue
        }

        It 'Returns false when no keys match' {
            $k8sConfigMap = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
config:
  app-mode: production
"@
            $tempFile = Join-Path $script:tempVault 'k8s-configmap.yaml'
            $k8sConfigMap | Out-File -FilePath $tempFile -Encoding utf8

            Test-FileContainsKeys -FilePath $tempFile `
                -EncryptedRegex '^(data|stringData)$' | Should -BeFalse
        }

        It 'Returns false for keys with similar names but not exact match' {
            $k8sFile = @"
apiVersion: v1
kind: Secret
metadata:
  name: test
data_backup: old-value
stringData_archive: archive
"@
            $tempFile = Join-Path $script:tempVault 'k8s-similar-keys.yaml'
            $k8sFile | Out-File -FilePath $tempFile -Encoding utf8

            Test-FileContainsKeys -FilePath $tempFile `
                -EncryptedRegex '^(data|stringData)$' | Should -BeFalse
        }
    }

    Context 'Error handling' {
        It 'Handles malformed YAML gracefully' {
            $badYaml = @"
this is not: [valid yaml
  unclosed: array
"@
            $tempFile = Join-Path $script:tempVault 'bad.yaml'
            $badYaml | Out-File -FilePath $tempFile -Encoding utf8

            Test-FileContainsKeys -FilePath $tempFile `
                -EncryptedRegex '^(data)$' -WarningAction SilentlyContinue | Should -BeFalse
        }

        It 'Handles non-existent file gracefully' {
            $nonExistentFile = Join-Path $script:tempVault 'does-not-exist.yaml'

            Test-FileContainsKeys -FilePath $nonExistentFile `
                -EncryptedRegex '^(data)$' -WarningAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-SopsEncryptionCandidates Integration Tests' {
    BeforeAll {
        $script:testVaultPath = Join-Path $PSScriptRoot 'TestData'
    }

    Context 'File discovery and filtering' {
        It 'Returns unencrypted files matching .sops.yaml rules' {
            $candidates = Get-SopsEncryptionCandidates -Path $script:testVaultPath

            $k8sPlainFile = Join-Path $script:testVaultPath 'k8s-secret-plain.yaml'
            $candidates | Should -Contain $k8sPlainFile
        }

        It 'Excludes already-encrypted files' {
            $candidates = Get-SopsEncryptionCandidates -Path $script:testVaultPath

            $encryptedFile = Join-Path $script:testVaultPath 'credentials.yaml'
            $candidates | Should -Not -Contain $encryptedFile
        }

        It 'Excludes files with unencrypted_suffix' {
            $candidates = Get-SopsEncryptionCandidates -Path $script:testVaultPath

            $unencryptedFile = Join-Path $script:testVaultPath 'config_unencrypted.yaml'
            $candidates | Should -Not -Contain $unencryptedFile
        }

        It 'Excludes .sops.yaml itself' {
            $candidates = Get-SopsEncryptionCandidates -Path $script:testVaultPath

            $sopsConfig = Join-Path $script:testVaultPath '.sops.yaml'
            $candidates | Should -Not -Contain $sopsConfig
        }

        It 'Respects encrypted_regex for content filtering' {
            $candidates = Get-SopsEncryptionCandidates -Path $script:testVaultPath

            # k8s-config-plain.yaml has no data/stringData keys
            $configFile = Join-Path $script:testVaultPath 'migration\k8s-config-plain.yaml'
            $candidates | Should -Not -Contain $configFile
        }

        It 'Returns empty array when no .sops.yaml found' {
            $emptyVault = Join-Path $TestDrive 'empty-vault'
            $null = New-Item -Path $emptyVault -ItemType Directory -Force

            $candidates = Get-SopsEncryptionCandidates -Path $emptyVault -WarningAction SilentlyContinue
            $candidates | Should -BeNullOrEmpty
        }
    }

    Context 'First-match rule semantics' {
        It 'Applies first matching rule and stops processing' {
            $tempVault = Join-Path $TestDrive 'rule-order-vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $tempVault 'migration') -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: migration[/\\].*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1test123
  - path_regex: \.yaml$
    age: age1test456
"@
            $sopsYaml | Out-File -FilePath (Join-Path $tempVault '.sops.yaml') -Encoding utf8

            $migrationFile = @"
apiVersion: v1
kind: Secret
stringData:
  key: value
"@
            $migrationFilePath = Join-Path $tempVault 'migration\secret.yaml'
            $migrationFile | Out-File -FilePath $migrationFilePath -Encoding utf8

            $candidates = Get-SopsEncryptionCandidates -Path $tempVault
            $candidates | Should -Contain $migrationFilePath
        }
    }

    Context 'Error handling and edge cases' {
        It 'Handles vault with only encrypted files' {
            $tempVault = Join-Path $TestDrive 'all-encrypted-vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    age: age1test123
"@
            $sopsYaml | Out-File -FilePath (Join-Path $tempVault '.sops.yaml') -Encoding utf8

            $sourceEncrypted = Join-Path $script:testVaultPath 'credentials.yaml'
            Copy-Item -Path $sourceEncrypted -Destination (Join-Path $tempVault 'credentials.yaml')

            $candidates = Get-SopsEncryptionCandidates -Path $tempVault
            $candidates | Should -BeNullOrEmpty
        }

        It 'Handles empty vault directory' {
            $emptyVault = Join-Path $TestDrive 'truly-empty-vault'
            $null = New-Item -Path $emptyVault -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    age: age1test123
"@
            $sopsYaml | Out-File -FilePath (Join-Path $emptyVault '.sops.yaml') -Encoding utf8

            $candidates = Get-SopsEncryptionCandidates -Path $emptyVault
            $candidates | Should -BeNullOrEmpty
        }

        It 'Extracts file patterns from path_regex rules' {
            $tempVault = Join-Path $TestDrive 'pattern-extraction-vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    age: age1test123
"@
            $sopsYaml | Out-File -FilePath (Join-Path $tempVault '.sops.yaml') -Encoding utf8

            'key: value' | Out-File -FilePath (Join-Path $tempVault 'config.yaml') -Encoding utf8
            'text' | Out-File -FilePath (Join-Path $tempVault 'readme.txt') -Encoding utf8

            $candidates = Get-SopsEncryptionCandidates -Path $tempVault
            $candidates | Should -Contain (Join-Path $tempVault 'config.yaml')
            $candidates | Should -Not -Contain (Join-Path $tempVault 'readme.txt')
        }

        It 'Always recurses through subdirectories' {
            $tempVault = Join-Path $TestDrive 'always-recurse-vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $tempVault 'subdir\nested') -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    age: age1test123
"@
            $sopsYaml | Out-File -FilePath (Join-Path $tempVault '.sops.yaml') -Encoding utf8

            'key: value' | Out-File -FilePath (Join-Path $tempVault 'root.yaml') -Encoding utf8
            'key: value' | Out-File -FilePath (Join-Path $tempVault 'subdir\mid.yaml') -Encoding utf8
            'key: value' | Out-File -FilePath (Join-Path $tempVault 'subdir\nested\deep.yaml') -Encoding utf8

            $candidates = Get-SopsEncryptionCandidates -Path $tempVault
            $candidates.Count | Should -Be 3
            $candidates | Should -Contain (Join-Path $tempVault 'root.yaml')
            $candidates | Should -Contain (Join-Path $tempVault 'subdir\mid.yaml')
            $candidates | Should -Contain (Join-Path $tempVault 'subdir\nested\deep.yaml')
        }

        It 'Handles multiple file extensions from different rules' {
            $tempVault = Join-Path $TestDrive 'multi-extension-vault'
            $null = New-Item -Path $tempVault -ItemType Directory -Force

            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    age: age1test123
  - path_regex: \.json$
    age: age1test456
"@
            $sopsYaml | Out-File -FilePath (Join-Path $tempVault '.sops.yaml') -Encoding utf8

            'key: value' | Out-File -FilePath (Join-Path $tempVault 'config.yaml') -Encoding utf8
            '{"key": "value"}' | Out-File -FilePath (Join-Path $tempVault 'config.json') -Encoding utf8
            'text' | Out-File -FilePath (Join-Path $tempVault 'readme.txt') -Encoding utf8

            $candidates = Get-SopsEncryptionCandidates -Path $tempVault
            $candidates | Should -Contain (Join-Path $tempVault 'config.yaml')
            $candidates | Should -Contain (Join-Path $tempVault 'config.json')
            $candidates | Should -Not -Contain (Join-Path $tempVault 'readme.txt')
        }
    }
}
