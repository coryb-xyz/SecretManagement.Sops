#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pipeline Support Tests for SecretManagement.Sops

.DESCRIPTION
    Test suite validating pipeline functionality for Set-Secret:
    - Pipeline input collection
    - Field deduplication (last value wins)
    - SOPS invocation optimization
    - Mixed input types
    - Error handling

.NOTES
    Run with: Invoke-Pester -Path .\Tests\PipelineSupport.Tests.ps1 -Tag 'Pipeline'
#>

BeforeAll {
    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    # Auto-bootstrap test data
    if (-not (Initialize-TestDataIfMissing)) {
        throw "Cannot run tests: Test data initialization failed"
    }

    # Clean up orphaned test vaults
    Remove-OrphanedTestVaults

    # Save original environment
    $script:OriginalEnvironment = Save-SopsEnvironment

    # Import main module
    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    # Import SecretManagement module
    if (-not (Get-Module Microsoft.PowerShell.SecretManagement -ListAvailable)) {
        throw "Microsoft.PowerShell.SecretManagement module required"
    }
    Import-Module Microsoft.PowerShell.SecretManagement -Force

    # Configure test environment
    $testDataPath = Join-Path $PSScriptRoot 'TestData'
    $testKeyFile = Join-Path $testDataPath 'test-key.txt'
    if (Test-Path $testKeyFile) {
        $env:SOPS_AGE_KEY_FILE = $testKeyFile
    }
    else {
        throw "Test key file not found: $testKeyFile"
    }
}

AfterAll {
    # Restore original environment
    if ($script:OriginalEnvironment) {
        Restore-SopsEnvironment -State $script:OriginalEnvironment
    }
}

Describe 'Set-Secret Pipeline Support' -Tag 'Pipeline', 'Integration' {
    BeforeAll {
        # Create test vault
        $script:TestSecretsPath = Join-Path $TestDrive 'pipeline-secrets'
        New-Item -Path $script:TestSecretsPath -ItemType Directory -Force | Out-Null

        # Create .sops.yaml
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

        # Register test vault
        $script:TestVaultName = New-IsolatedTestVault -BaseName 'SopsPipelineTest' -ModulePath $modulePath -VaultParameters @{
            Path        = $script:TestSecretsPath
            FilePattern = '*.yaml'
            Recurse     = $false
        }
    }

    AfterAll {
        # Unregister test vault
        if ($script:TestVaultName) {
            Remove-IsolatedTestVault -VaultName $script:TestVaultName
        }
    }

    Context 'Basic Pipeline Functionality' {
        It 'Collects multiple piped string path values' {
            $secretName = "pipeline-basic-$(New-Guid)"
            $initial = @{ field1 = 'old1'; field2 = 'old2'; field3 = 'old3' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            # Pipeline update
            ".field1: new1", ".field2: new2" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.field1 | Should -Be 'new1'
            $parsed.field2 | Should -Be 'new2'
            $parsed.field3 | Should -Be 'old3'  # Preserved
        }

        It 'Works with single piped value' {
            $secretName = "pipeline-single-$(New-Guid)"
            $initial = @{ field = 'old' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            ".field: new" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.field | Should -Be 'new'
        }

        It 'Handles nested field paths in pipeline' {
            $secretName = "pipeline-nested-$(New-Guid)"
            $initial = @{
                stringData = @{
                    user = 'admin'
                    pass = 'old'
                }
            }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            ".stringData.pass: newpass", ".stringData.user: root" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.stringData.pass | Should -Be 'newpass'
            $parsed.stringData.user | Should -Be 'root'
        }
    }

    Context 'Deduplication' {
        It 'Deduplicates same field - last value wins' {
            $secretName = "dedup-test-$(New-Guid)"
            $initial = @{ field = 'initial' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            # Update same field three times - last should win
            ".field: first", ".field: second", ".field: final" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.field | Should -Be 'final'
        }

        It 'Deduplicates mixed unique and duplicate fields' {
            $secretName = "dedup-mixed-$(New-Guid)"
            $initial = @{ a = '1'; b = '2'; c = '3' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            ".a: A1", ".b: B1", ".a: A2", ".c: C1", ".a: A3" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.a | Should -Be 'A3'  # Last a value
            $parsed.b | Should -Be 'B1'  # Only b value
            $parsed.c | Should -Be 'C1'  # Only c value
        }
    }

    Context 'Null Value Handling' {
        It 'Handles null values to unset fields via pipeline' {
            $secretName = "null-test-$(New-Guid)"
            $initial = @{ keep = 'value'; remove1 = 'old'; remove2 = 'old' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            ".remove1: null", ".remove2: null" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.keep | Should -Be 'value'
            $parsed.PSObject.Properties.Name | Should -Not -Contain 'remove1'
            $parsed.PSObject.Properties.Name | Should -Not -Contain 'remove2'
        }
    }

    Context 'Mixed Input Types' {
        It 'Handles mix of string paths and hashtables' {
            $secretName = "mixed-types-$(New-Guid)"
            $initial = @{ a = '1'; b = '2'; c = '3' }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            # Mix string path and hashtable
            ".a: updated", @{ b = 'hashtable' } |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.a | Should -Be 'updated'
            $parsed.b | Should -Be 'hashtable'
            $parsed.c | Should -Be '3'  # Preserved
        }
    }

    Context 'New File Creation via Pipeline' {
        It 'Creates new secret file from piped values' {
            $secretName = "pipeline-new-$(New-Guid)"

            ".field1: value1", ".field2: value2" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.field1 | Should -Be 'value1'
            $parsed.field2 | Should -Be 'value2'
        }

        It 'Deduplicates even when creating new file' {
            $secretName = "pipeline-new-dedup-$(New-Guid)"

            ".field: first", ".field: second", ".field: final" |
                Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.field | Should -Be 'final'
        }
    }

    Context 'Type Preservation' {
        It 'Preserves data types through pipeline updates' {
            $secretName = "type-preserve-$(New-Guid)"
            $initial = @{
                str  = 'text'
                num  = 42
                bool = $true
            }
            Set-Secret -Name $secretName -Secret $initial -Vault $script:TestVaultName

            ".str: newtext" | Set-Secret -Name $secretName -Vault $script:TestVaultName

            $result = Get-Secret -Name $secretName -Vault $script:TestVaultName -AsPlainText
            $parsed = $result | ConvertFrom-Yaml
            $parsed.str | Should -BeOfType [string]
            $parsed.num | Should -BeOfType [int]
            $parsed.bool | Should -BeOfType [bool]
        }
    }
}
