BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot '..' 'SecretManagement.Sops'
    Import-Module (Join-Path $modulePath 'SecretManagement.Sops.psd1') -Force

    # Dot-source Private functions for testing
    . (Join-Path $modulePath 'Private' 'Test-SopsPathMatch.ps1')
    . (Join-Path $modulePath 'Private' 'Test-SopsContentMatch.ps1')
    . (Join-Path $modulePath 'Private' 'Get-SopsConfiguration.ps1')
    . (Join-Path $modulePath 'Private' 'Test-SopsEncrypted.ps1')

    $testDataPath = Join-Path $PSScriptRoot 'TestData'
}

Describe 'Test-SopsPathMatch' {
    Context 'Path Regex Matching' {
        It 'Matches path against simple regex pattern' {
            $rules = @(
                @{ PathRegex = '\.yaml$' }
            )

            $match = Test-SopsPathMatch -FilePath 'C:\vault\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules

            $match.Matched | Should -BeTrue
            $match.MatchedRule | Should -Not -BeNull
            $match.MatchedRule.PathRegex | Should -Be '\.yaml$'
        }

        It 'Matches path against complex pattern with directory separators' {
            $rules = @(
                @{ PathRegex = 'migration[/\\].*\.yaml$' }
            )

            $match = Test-SopsPathMatch -FilePath 'C:\vault\migration\k8s-secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules

            $match.Matched | Should -BeTrue
        }

        It 'Returns false when path does not match any rule' {
            $rules = @(
                @{ PathRegex = 'migration[/\\].*\.yaml$' }
            )

            $match = Test-SopsPathMatch -FilePath 'C:\vault\other\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules

            $match.Matched | Should -BeFalse
            $match.MatchedRule | Should -BeNull
        }

        It 'Returns first matching rule when multiple rules match' {
            $rules = @(
                @{ PathRegex = '\.yaml$'; EncryptedRegex = '^data$' }
                @{ PathRegex = '.*'; EncryptedRegex = '^stringData$' }
            )

            $match = Test-SopsPathMatch -FilePath 'C:\vault\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules

            $match.Matched | Should -BeTrue
            $match.MatchedRule.EncryptedRegex | Should -Be '^data$'
        }

        It 'Handles invalid regex gracefully' {
            $rules = @(
                @{ PathRegex = '[invalid(' }
            )

            $match = Test-SopsPathMatch -FilePath 'C:\vault\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules -WarningAction SilentlyContinue

            $match.Matched | Should -BeFalse
        }

        It 'Normalizes Windows backslashes to forward slashes' {
            $rules = @(
                @{ PathRegex = 'apps/prod/.*\.yaml$' }
            )

            # Windows path with backslashes should match forward slash regex
            $match = Test-SopsPathMatch -FilePath 'C:\vault\apps\prod\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules

            $match.Matched | Should -BeTrue
        }
    }
}

Describe 'Test-SopsContentMatch' {
    BeforeAll {
        $tempDir = Join-Path $TestDrive 'content-tests'
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    Context 'encrypted_regex Filter' {
        It 'Returns true when YAML contains key matching encrypted_regex' {
            $yamlPath = Join-Path $tempDir 'k8s-secret.yaml'
            @'
apiVersion: v1
kind: Secret
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^data$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue
        }

        It 'Returns false when YAML has no keys matching encrypted_regex' {
            $yamlPath = Join-Path $tempDir 'k8s-config.yaml'
            @'
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^(data|stringData)$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }

        It 'Handles Kubernetes Secret with data and stringData keys' {
            $yamlPath = Join-Path $tempDir 'k8s-secret-both.yaml'
            @'
apiVersion: v1
kind: Secret
stringData:
  username: admin
data:
  password: cGFzc3dvcmQ=
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^(data|stringData)$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue
        }
    }

    Context 'encrypted_suffix Filter' {
        It 'Returns true when YAML contains key with encrypted_suffix' {
            $yamlPath = Join-Path $tempDir 'suffix-test.yaml'
            @'
database_host: localhost
database_password_secret: mypassword
api_key_secret: abc123
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedSuffix = '_secret' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue
        }

        It 'Returns false when no keys have encrypted_suffix' {
            $yamlPath = Join-Path $tempDir 'no-suffix.yaml'
            @'
database_host: localhost
api_endpoint: https://api.example.com
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedSuffix = '_secret' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }
    }

    Context 'unencrypted_regex Filter' {
        It 'Returns true when YAML has keys NOT matching unencrypted_regex' {
            $yamlPath = Join-Path $tempDir 'unencrypted-regex.yaml'
            @'
public_key: value1
private_key: value2
metadata: value3
'@ | Set-Content -Path $yamlPath

            $rule = @{ UnencryptedRegex = '^public_' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue  # private_key and metadata should be encrypted
        }

        It 'Returns false when all keys match unencrypted_regex' {
            $yamlPath = Join-Path $tempDir 'all-public.yaml'
            @'
public_key1: value1
public_key2: value2
public_metadata: value3
'@ | Set-Content -Path $yamlPath

            $rule = @{ UnencryptedRegex = '^public_' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse  # All keys start with public_, nothing to encrypt
        }
    }

    Context 'unencrypted_suffix Filter' {
        It 'Returns true when YAML has keys without unencrypted_suffix' {
            $yamlPath = Join-Path $tempDir 'mixed-suffix.yaml'
            @'
database_config_unencrypted: localhost
database_password: secret123
api_endpoint_unencrypted: https://api.example.com
'@ | Set-Content -Path $yamlPath

            $rule = @{ UnencryptedSuffix = '_unencrypted' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue  # database_password should be encrypted
        }

        It 'Returns false when all keys have unencrypted_suffix' {
            $yamlPath = Join-Path $tempDir 'all-unencrypted-suffix.yaml'
            @'
database_config_unencrypted: localhost
api_endpoint_unencrypted: https://api.example.com
'@ | Set-Content -Path $yamlPath

            $rule = @{ UnencryptedSuffix = '_unencrypted' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse  # Nothing to encrypt
        }
    }

    Context 'No Filter (Encrypt All)' {
        It 'Returns true when rule has no content filter' {
            $yamlPath = Join-Path $tempDir 'no-filter.yaml'
            @'
key1: value1
key2: value2
'@ | Set-Content -Path $yamlPath

            $rule = @{}  # No content filter
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeTrue  # All values should be encrypted
        }

        It 'Returns false for empty YAML file' {
            $yamlPath = Join-Path $tempDir 'empty.yaml'
            '' | Set-Content -Path $yamlPath

            $rule = @{}
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }
    }

    Context 'Edge Cases' {
        It 'Handles malformed YAML gracefully' {
            $yamlPath = Join-Path $tempDir 'malformed.yaml'
            @'
this is not:
  valid: yaml
  [broken
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^data$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule -WarningAction SilentlyContinue

            $result | Should -BeFalse
        }

        It 'Handles non-dictionary YAML (scalar)' {
            $yamlPath = Join-Path $tempDir 'scalar.yaml'
            'just a string' | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^data$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }

        It 'Handles non-dictionary YAML (array)' {
            $yamlPath = Join-Path $tempDir 'array.yaml'
            @'
- item1
- item2
- item3
'@ | Set-Content -Path $yamlPath

            $rule = @{ EncryptedRegex = '^data$' }
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }

        It 'Handles YAML with no keys (empty dictionary)' {
            $yamlPath = Join-Path $tempDir 'empty-dict.yaml'
            '{}' | Set-Content -Path $yamlPath

            $rule = @{}
            $result = Test-SopsContentMatch -FilePath $yamlPath -CreationRule $rule

            $result | Should -BeFalse
        }
    }
}

Describe 'Get-SopsConfiguration Extensions' {
    It 'Extracts all creation_rules fields' {
        $config = Get-SopsConfiguration -VaultPath $testDataPath

        $config.Found | Should -BeTrue
        $config.CreationRules | Should -Not -BeNullOrEmpty
        $config.CreationRules.Count | Should -BeGreaterThan 0

        # First rule should have encrypted_regex (migration path)
        $config.CreationRules[0].PathRegex | Should -Be 'migration[/\\].*\.yaml$'
        $config.CreationRules[0].EncryptedRegex | Should -Be '^(data|stringData)$'

        # Second rule should have unencrypted_suffix (catch-all)
        $config.CreationRules[1].PathRegex | Should -Be '\.yaml$'
        $config.CreationRules[1].UnencryptedSuffix | Should -Be '_unencrypted'
    }

    It 'Maintains backward compatibility (UnencryptedSuffixes still works)' {
        $config = Get-SopsConfiguration -VaultPath $testDataPath

        $config.UnencryptedSuffixes | Should -Contain '_unencrypted'
    }
}

Describe 'Get-SecretIndex with RequireSopsMatch' {
    Context 'Default Behavior' {
        It 'Includes all files when RequireSopsMatch is false (default)' {
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $false

            # Should include encrypted and unencrypted files
            $index.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Filtered Behavior (RequireSopsMatch=$true)' {
        It 'Includes plaintext files matching .sops.yaml rules with encryptable content' {
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $true

            # Should include migration/k8s-secret-plain.yaml
            $k8sSecret = $index | Where-Object { $_.Name -like '*k8s-secret-plain*' }
            $k8sSecret | Should -Not -BeNullOrEmpty
        }

        It 'Excludes files already encrypted by SOPS' {
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $true

            # Should NOT include any encrypted SOPS files
            foreach ($entry in $index) {
                $isEncrypted = Test-SopsEncrypted -FilePath $entry.FilePath
                $isEncrypted | Should -BeFalse
            }
        }

        It 'Includes plaintext files matching catch-all rule with encryptable content' {
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $true

            # Should include no-match-plain.yaml (matches \.yaml$ catch-all rule with no content filter)
            $noMatch = $index | Where-Object { $_.Name -like '*no-match-plain*' }
            $noMatch | Should -Not -BeNullOrEmpty
        }

        It 'Excludes plaintext files with no encryptable content' {
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $true

            # Should NOT include migration/k8s-config-plain.yaml (has no data/stringData keys)
            $configMap = $index | Where-Object { $_.Name -like '*k8s-config-plain*' }
            $configMap | Should -BeNullOrEmpty
        }

        It 'Returns empty array when no .sops.yaml exists' {
            $tempVault = Join-Path $TestDrive 'no-sops-config'
            New-Item -ItemType Directory -Path $tempVault -Force | Out-Null
            'key: value' | Set-Content -Path (Join-Path $tempVault 'test.yaml')

            $index = Get-SecretIndex -Path $tempVault -FilePattern '*.yaml' -RequireSopsMatch $true

            $index | Should -BeNullOrEmpty
        }
    }

    Context 'Integration with RequireEncryption' {
        It 'RequireEncryption takes precedence over RequireSopsMatch' {
            # When both are true, RequireEncryption should be used (returns only encrypted files)
            $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireEncryption $true -RequireSopsMatch $true

            # Should only include encrypted files, not unencrypted ones
            foreach ($entry in $index) {
                $isEncrypted = Test-SopsEncrypted -FilePath $entry.FilePath
                $isEncrypted | Should -BeTrue
            }
        }
    }
}

Describe 'GitOps Migration Workflow' -Tag 'Integration' {
    It 'Identifies and allows reading unencrypted K8s secrets' {
        # Find unencrypted secrets needing migration
        $index = Get-SecretIndex -Path $testDataPath -FilePattern '*.yaml' -Recurse $true -RequireSopsMatch $true

        $k8sSecret = $index | Where-Object { $_.Name -like '*k8s-secret-plain*' }
        $k8sSecret | Should -Not -BeNullOrEmpty

        # Verify we can read the plaintext content (for migration)
        $filePath = $k8sSecret.FilePath
        Test-Path $filePath | Should -BeTrue

        $content = Get-Content $filePath -Raw | ConvertFrom-Yaml
        $content.stringData.username | Should -Be 'akv://prod-kv/db-username'
    }
}
