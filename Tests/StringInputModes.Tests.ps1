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

Describe 'Set-Secret with String Input Modes' -Tag 'StringInputModes', 'Integration' {
    BeforeAll {
        $script:TestSecretsPath = Join-Path $TestDrive 'string-modes'
        $null = New-Item -Path $script:TestSecretsPath -ItemType Directory -Force

        $testDataPath = Join-Path $PSScriptRoot 'TestData'
        $testKeyFile = Join-Path $testDataPath 'test-key.txt'

        if (Test-Path $testKeyFile) {
            $ageKeyContent = Get-Content $testKeyFile -Raw
            if ($ageKeyContent -match 'public key: (.+)') {
                $agePublicKey = $Matches[1].Trim()
                $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
                Set-Content -Path (Join-Path $script:TestSecretsPath '.sops.yaml') -Value $sopsConfig
            }
        }

        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsStringModeTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
        }
    }

    AfterAll {
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'Path-based syntax updates' -Tag 'PathSyntax' {
        It 'Updates single nested field with path syntax' {
            $secretName = "path-test-$(New-Guid)"

            try {
                $k8sSecret = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{ name = 'test-secret' }
                    stringData = @{
                        password = 'oldPassword'
                        username = 'admin'
                    }
                }
                Set-Secret -Name $secretName -Secret $k8sSecret -Vault $script:TestVaultName

                ".stringData.password: newPassword" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml
                $parsed.stringData.password | Should -Be 'newPassword'
                $parsed.stringData.username | Should -Be 'admin'
                $parsed.kind | Should -Be 'Secret'

                # Verify no literal ".stringData.password" key at root level
                $parsed.PSObject.Properties.Name | Should -Not -Contain '.stringData.password'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Updates multiple fields with multiple path syntax calls' {
            $secretName = "multi-path-$(New-Guid)"

            try {
                $initial = @{
                    host     = 'old.example.com'
                    port     = 5432
                    database = 'olddb'
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                ".host: new.example.com" | Set-Secret -Name $secretName -Vault $script:TestVaultName
                ".database: newdb" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                $parsed.host | Should -Be 'new.example.com'
                $parsed.database | Should -Be 'newdb'
                $parsed.port | Should -Be 5432

                $parsed.PSObject.Properties.Name | Should -Not -Contain '.host'
                $parsed.PSObject.Properties.Name | Should -Not -Contain '.database'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'YAML patching mode' -Tag 'YAMLPatching' {
        It 'Patches multiple fields while preserving others' {
            $secretName = "yaml-patch-$(New-Guid)"

            try {
                $initial = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{
                        name      = 'postgres'
                        namespace = 'production'
                    }
                    stringData = @{
                        host     = 'postgres.prod.example.com'
                        username = 'prod_user'
                        password = 'oldPassword'
                        port     = '5432'
                    }
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                $patch = @"
stringData:
  password: newPassword
  username: new_admin
"@
                $patch | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'password:\s*newPassword'
                $retrieved | Should -Match 'username:\s*new_admin'
                $retrieved | Should -Match 'host:\s*postgres\.prod\.example\.com'
                $retrieved | Should -Match 'port:\s*"?5432"?'
                $retrieved | Should -Match 'kind:\s*Secret'
                $retrieved | Should -Match 'namespace:\s*production'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Updates nested structures with YAML' {
            $secretName = "nested-yaml-$(New-Guid)"

            try {
                $initial = @{
                    config = @{
                        database = @{
                            host = 'old.db.com'
                            port = 3306
                        }
                        cache    = @{
                            host = 'old.cache.com'
                        }
                    }
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                $patch = @"
config:
  database:
    host: new.db.com
"@
                $patch | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'host:\s*new\.db\.com'
                $retrieved | Should -Match 'port:\s*3306'
                $retrieved | Should -Match 'cache:'
                $retrieved | Should -Match 'host:\s*old\.cache\.com'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Plain string mode (backward compatibility)' -Tag 'PlainString' {
        It 'Stores plain string in value key' {
            $secretName = "plain-$(New-Guid)"

            try {
                Set-Secret -Name $secretName -Secret 'simple-password-123' -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'value:\s*simple-password-123'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Updates plain string value' {
            $secretName = "plain-update-$(New-Guid)"

            try {
                Set-Secret -Name $secretName -Secret 'password1' -Vault $script:TestVaultName
                Set-Secret -Name $secretName -Secret 'password2' -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'value:\s*password2'
                $retrieved | Should -Not -Match 'password1'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Real-world scenarios' -Tag 'Scenarios' {
        It 'Kubernetes secret workflow: create then update password' {
            $secretName = "k8s-workflow-$(New-Guid)"

            try {
                $k8sSecret = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{
                        name      = 'postgres-prod'
                        namespace = 'web-app'
                    }
                    type       = 'Opaque'
                    stringData = @{
                        host     = 'postgres.prod.example.com'
                        username = 'prod_user'
                        password = 'ProductionPass123!'
                    }
                }
                Set-Secret -Name $secretName -Secret $k8sSecret -Vault $script:TestVaultName

                ".stringData.password: NewProductionPass456!" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                $parsed.stringData.password | Should -Be 'NewProductionPass456!'
                $parsed.stringData.password | Should -Not -Be 'ProductionPass123!'
                $parsed.stringData.username | Should -Be 'prod_user'
                $parsed.stringData.host | Should -Be 'postgres.prod.example.com'
                $parsed.metadata.namespace | Should -Be 'web-app'
                $parsed.kind | Should -Be 'Secret'

                $parsed.PSObject.Properties.Name | Should -Not -Contain '.stringData.password'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Tab-indented YAML normalization' -Tag 'TabNormalization' {
        It 'Patches with tab-indented YAML after normalization' {
            $secretName = "tab-yaml-$(New-Guid)"

            try {
                $initial = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{
                        name      = 'postgres-prod'
                        namespace = 'web-app'
                    }
                    type       = 'Opaque'
                    stringData = @{
                        username = 'prod_user'
                        password = 'oldPass'
                        host     = 'db.example.com'
                    }
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                # Tab-indented YAML simulating copy/paste from Get-Secret
                $tabYaml = @"
stringData:
`tusername: prod_user2
`tpassword: newPass
"@
                $tabYaml | Set-Secret -Name $secretName -Vault $script:TestVaultName -Verbose

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                $parsed.stringData.username | Should -Be 'prod_user2'
                $parsed.stringData.password | Should -Be 'newPass'
                $parsed.stringData.host | Should -Be 'db.example.com'
                $parsed.kind | Should -Be 'Secret'
                $parsed.metadata.namespace | Should -Be 'web-app'
                $parsed.PSObject.Properties.Name | Should -Not -Contain 'value'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Handles full K8s secret with tab indentation' {
            $secretName = "full-tab-k8s-$(New-Guid)"

            try {
                $initial = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{
                        name      = 'postgres-prod'
                        namespace = 'web-app'
                    }
                    type       = 'Opaque'
                    stringData = @{
                        username = 'prod_user'
                        password = 'oldPass'
                    }
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                $fullTabYaml = @"
apiVersion: v1
kind: Secret
metadata:
`tname: postgres-prod
`tnamespace: web-app
type: Opaque
stringData:
`tusername: prod_user2
`tpassword: newPass
"@
                $fullTabYaml | Set-Secret -Name $secretName -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                $parsed.stringData.username | Should -Be 'prod_user2'
                $parsed.stringData.password | Should -Be 'newPass'
                $parsed.PSObject.Properties.Name | Should -Not -Contain 'value'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Stores plain strings with colons in value key (not as YAML)' {
            $secretName = "plain-colon-$(New-Guid)"

            try {
                $connectionString = "postgresql://user:pass@host:5432/database"
                Set-Secret -Name $secretName -Secret $connectionString -Vault $script:TestVaultName

                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'value:\s*postgresql://user:pass@host:5432/database'

                $parsed = $retrieved | ConvertFrom-Yaml
                $parsed.value | Should -Be $connectionString
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Throws helpful error for truly malformed YAML' {
            $secretName = "malformed-$(New-Guid)"

            try {
                $initial = @{ key = 'value' }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                # Malformed YAML with mixed tabs and spaces that breaks structure
                $malformedYaml = @"
stringData:
`t  username: value
  password: value
"@

                { $malformedYaml | Set-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction Stop } |
                    Should -Throw '*Unable to add secret*'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }
}
