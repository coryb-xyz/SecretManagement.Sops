#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for Set-Secret string input modes (path syntax, YAML patching, plain strings).

.DESCRIPTION
    Validates the three string input modes:
    1. Path-based syntax (.path.to.field: value) for targeted updates
    2. YAML content for multi-field patching
    3. Plain strings for backward compatibility

.NOTES
    Run with: Invoke-Pester -Path .\Tests\StringInputModes.Tests.ps1 -Tag 'StringInputModes'
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

Describe 'Set-Secret with String Input Modes' -Tag 'StringInputModes', 'Integration' {
    BeforeAll {
        # Create test vault
        $script:TestSecretsPath = Join-Path $TestDrive 'string-modes'
        New-Item -Path $script:TestSecretsPath -ItemType Directory -Force | Out-Null

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
    age: $agePublicKey
"@
                Set-Content -Path (Join-Path $script:TestSecretsPath '.sops.yaml') -Value $sopsConfig
            }
        }

        # Register vault with unique isolated name
        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsStringModeTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
        }
        Write-Verbose "Registered isolated test vault: $script:TestVaultName"
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
                # Create initial secret
                $k8sSecret = @{
                    apiVersion = 'v1'
                    kind       = 'Secret'
                    metadata   = @{
                        name = 'test-secret'
                    }
                    stringData = @{
                        password = 'oldPassword'
                        username = 'admin'
                    }
                }
                Set-Secret -Name $secretName -Secret $k8sSecret -Vault $script:TestVaultName

                # Update just the password using path syntax
                ".stringData.password: newPassword" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                # Verify the update
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText

                # Parse YAML and verify structure (not just pattern matching)
                $parsed = $retrieved | ConvertFrom-Yaml
                $parsed.stringData.password | Should -Be 'newPassword'
                $parsed.stringData.username | Should -Be 'admin'  # Should be preserved
                $parsed.kind | Should -Be 'Secret'                # Should be preserved

                # CRITICAL: Verify no literal ".stringData.password" key at root level
                # This catches the regression where path syntax is parsed as YAML
                $parsed.PSObject.Properties.Name | Should -Not -Contain '.stringData.password'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Updates multiple fields with multiple path syntax calls' {
            $secretName = "multi-path-$(New-Guid)"

            try {
                # Create initial secret
                $initial = @{
                    host     = 'old.example.com'
                    port     = 5432
                    database = 'olddb'
                }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                # Update multiple fields
                ".host: new.example.com" | Set-Secret -Name $secretName -Vault $script:TestVaultName
                ".database: newdb" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                # Verify all updates and preservation
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                # Verify structure (not pattern matching)
                $parsed.host | Should -Be 'new.example.com'
                $parsed.database | Should -Be 'newdb'
                $parsed.port | Should -Be 5432

                # CRITICAL: No literal ".host" or ".database" keys at root level
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
                # Create initial secret
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

                # Patch with YAML (update password and username only)
                $patch = @"
stringData:
  password: newPassword
  username: new_admin
"@
                $patch | Set-Secret -Name $secretName -Vault $script:TestVaultName

                # Verify updates and preservation
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'password:\s*newPassword'
                $retrieved | Should -Match 'username:\s*new_admin'
                $retrieved | Should -Match 'host:\s*postgres\.prod\.example\.com'  # Preserved
                $retrieved | Should -Match 'port:\s*"?5432"?'                      # Preserved (may be quoted)
                $retrieved | Should -Match 'kind:\s*Secret'                        # Preserved
                $retrieved | Should -Match 'namespace:\s*production'               # Preserved
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Updates nested structures with YAML' {
            $secretName = "nested-yaml-$(New-Guid)"

            try {
                # Create initial secret
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

                # Patch nested structure
                $patch = @"
config:
  database:
    host: new.db.com
"@
                $patch | Set-Secret -Name $secretName -Vault $script:TestVaultName

                # Verify update and preservation
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'host:\s*new\.db\.com'
                $retrieved | Should -Match 'port:\s*3306'           # Preserved
                $retrieved | Should -Match 'cache:'                 # Preserved
                $retrieved | Should -Match 'host:\s*old\.cache\.com' # Cache host preserved
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
                # Initial K8s secret creation
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

                # Later: rotate password using path syntax
                ".stringData.password: NewProductionPass456!" | Set-Secret -Name $secretName -Vault $script:TestVaultName

                # Verify rotation
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                # Verify nested structure (not pattern matching)
                $parsed.stringData.password | Should -Be 'NewProductionPass456!'
                $parsed.stringData.password | Should -Not -Be 'ProductionPass123!'

                # Verify everything else preserved
                $parsed.stringData.username | Should -Be 'prod_user'
                $parsed.stringData.host | Should -Be 'postgres.prod.example.com'
                $parsed.metadata.namespace | Should -Be 'web-app'
                $parsed.kind | Should -Be 'Secret'

                # CRITICAL: No literal ".stringData.password" key at root level
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
                # Create initial secret
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

                # Patch with tab-indented YAML (simulating copy/paste from Get-Secret)
                # Note: Using actual tab character ("`t") in the here-string
                $tabYaml = @"
stringData:
`tusername: prod_user2
`tpassword: newPass
"@
                $tabYaml | Set-Secret -Name $secretName -Vault $script:TestVaultName -Verbose

                # Verify strategic merge worked
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                # Updated fields
                $parsed.stringData.username | Should -Be 'prod_user2'
                $parsed.stringData.password | Should -Be 'newPass'

                # Preserved fields
                $parsed.stringData.host | Should -Be 'db.example.com'
                $parsed.kind | Should -Be 'Secret'
                $parsed.metadata.namespace | Should -Be 'web-app'

                # CRITICAL: Should NOT have added a 'value' key
                $parsed.PSObject.Properties.Name | Should -Not -Contain 'value'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Handles full K8s secret with tab indentation' {
            $secretName = "full-tab-k8s-$(New-Guid)"

            try {
                # Create initial secret
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

                # Update with fully tab-indented YAML (realistic copy/paste scenario)
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

                # Verify merge
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $parsed = $retrieved | ConvertFrom-Yaml

                $parsed.stringData.username | Should -Be 'prod_user2'
                $parsed.stringData.password | Should -Be 'newPass'

                # CRITICAL: No 'value' key
                $parsed.PSObject.Properties.Name | Should -Not -Contain 'value'
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Stores plain strings with colons in value key (not as YAML)' {
            $secretName = "plain-colon-$(New-Guid)"

            try {
                # Connection string with colons but no newlines - should be plain string
                $connectionString = "postgresql://user:pass@host:5432/database"
                Set-Secret -Name $secretName -Secret $connectionString -Vault $script:TestVaultName

                # Verify stored as plain value
                $retrieved = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
                $retrieved | Should -Match 'value:\s*postgresql://user:pass@host:5432/database'

                # Parse to verify structure
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
                # Create initial secret
                $initial = @{ key = 'value' }
                Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

                # Malformed YAML with tab that creates invalid syntax
                # (mixing tabs and spaces in a way that breaks YAML structure)
                $malformedYaml = @"
stringData:
`t  username: value
  password: value
"@

                # Should throw with helpful error message
                # Note: SecretManagement wraps our error in a generic message
                { $malformedYaml | Set-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction Stop } |
                    Should -Throw
            }
            finally {
                Remove-Secret -Name $secretName -Vault $script:TestVaultName -ErrorAction SilentlyContinue
            }
        }
    }
}
