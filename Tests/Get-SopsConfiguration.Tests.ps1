BeforeAll {
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    $script:testState = Initialize-TestEnvironment

    $functionPath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops' 'Private' 'Get-SopsConfiguration.ps1'
    . $functionPath

    Import-Module powershell-yaml -ErrorAction Stop
}

AfterAll {
    Restore-TestEnvironment -State $script:testState
}

Describe 'Get-SopsConfiguration' {
    BeforeAll {
        $script:testVaultPath = Join-Path $TestDrive 'test-vault'
        $null = New-Item -Path $script:testVaultPath -ItemType Directory -Force
    }

    Context 'Basic functionality' {
        It 'Returns empty result when .sops.yaml does not exist' {
            $result = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $result.Found | Should -BeFalse
            $result.UnencryptedSuffixes | Should -BeNullOrEmpty
        }

        It 'Extracts unencrypted_suffix values' {
            $sopsYaml = @"
creation_rules:
  - path_regex: \.yaml$
    unencrypted_suffix: _unencrypted
    age: age1test123
"@
            $sopsYaml | Out-File -FilePath (Join-Path $script:testVaultPath '.sops.yaml') -Encoding utf8

            $result = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $result.Found | Should -BeTrue
            $result.UnencryptedSuffixes | Should -Contain '_unencrypted'
        }

        It 'Returns unique suffixes only' {
            $sopsYaml = @"
creation_rules:
  - path_regex: dev[/\\].*\.yaml$
    unencrypted_suffix: _plain
    age: age1test123
  - path_regex: prod[/\\].*\.yaml$
    unencrypted_suffix: _plain
    age: age1test456
"@
            $sopsYaml | Out-File -FilePath (Join-Path $script:testVaultPath '.sops.yaml') -Encoding utf8

            $result = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $result.UnencryptedSuffixes.Count | Should -Be 1
            $result.UnencryptedSuffixes | Should -Contain '_plain'
        }
    }

    Context 'CreationRules extraction' {
        BeforeEach {
            $sopsYaml = @"
creation_rules:
  - path_regex: migration[/\\].*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1test123
  - path_regex: \.yaml$
    unencrypted_suffix: _unencrypted
    age: age1test456
"@
            $sopsYaml | Out-File -FilePath (Join-Path $script:testVaultPath '.sops.yaml') -Encoding utf8
        }

        It 'Returns CreationRules array with path_regex' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.CreationRules | Should -Not -BeNullOrEmpty
            $config.CreationRules.Count | Should -Be 2
            $config.CreationRules[0].PathRegex | Should -Match 'migration'
            $config.CreationRules[1].PathRegex | Should -Be '\.yaml$'
        }

        It 'Extracts encrypted_regex when present' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.CreationRules[0].EncryptedRegex | Should -Be '^(data|stringData)$'
        }

        It 'Handles missing encrypted_regex gracefully' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.CreationRules[1].EncryptedRegex | Should -BeNullOrEmpty
        }

        It 'Extracts unencrypted_suffix per rule' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.CreationRules[0].UnencryptedSuffix | Should -BeNullOrEmpty
            $config.CreationRules[1].UnencryptedSuffix | Should -Be '_unencrypted'
        }

        It 'Maintains backward compatibility with UnencryptedSuffixes' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.UnencryptedSuffixes | Should -Contain '_unencrypted'
            $config.UnencryptedSuffixes.Count | Should -Be 1
        }

        It 'Handles rules with no unencrypted_suffix in backward compatibility' {
            $config = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $config.UnencryptedSuffixes | Should -Not -Contain $null
        }
    }

    Context 'Edge cases' {
        It 'Handles malformed YAML gracefully' {
            $badYaml = @"
creation_rules:
  - path_regex: test
    invalid: [unclosed array
"@
            $badYaml | Out-File -FilePath (Join-Path $script:testVaultPath '.sops.yaml') -Encoding utf8

            { Get-SopsConfiguration -VaultPath $script:testVaultPath -WarningAction SilentlyContinue } | Should -Not -Throw
            $result = Get-SopsConfiguration -VaultPath $script:testVaultPath -WarningAction SilentlyContinue
            $result.Found | Should -BeFalse
        }

        It 'Handles .sops.yaml with no creation_rules' {
            '# Empty config' | Out-File -FilePath (Join-Path $script:testVaultPath '.sops.yaml') -Encoding utf8

            $result = Get-SopsConfiguration -VaultPath $script:testVaultPath
            $result.CreationRules | Should -BeNullOrEmpty
            $result.Found | Should -BeFalse
        }
    }
}
