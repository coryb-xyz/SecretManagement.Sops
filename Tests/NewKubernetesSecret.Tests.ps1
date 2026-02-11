#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for New-KubernetesSecret.

.DESCRIPTION
    Validates Kubernetes Secret YAML generation, including:
    - Namespace omission when not specified
    - Namespace inclusion when specified
    - Output format options (YAML, JSON, Hashtable)

.NOTES
    Requires kubectl. Tests are skipped when kubectl is not installed.
    Run with: Invoke-Pester -Path .\Tests\NewKubernetesSecret.Tests.ps1 -Tag 'NewKubernetesSecret'
#>

BeforeAll {
    # Import the main module (New-KubernetesSecret is a Public function)
    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force

    $script:KubectlAvailable = $null -ne (Get-Command 'kubectl' -ErrorAction SilentlyContinue)
}

Describe 'New-KubernetesSecret' -Tag 'NewKubernetesSecret' {

    Context 'Namespace handling' -Tag 'Namespace' {
        It 'Omits namespace field from metadata when -Namespace is not specified' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ key = 'value' } -AsHashtable

            $result.metadata.ContainsKey('namespace') | Should -Be $false
        }

        It 'Includes namespace field when -Namespace is specified' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ key = 'value' } -Namespace 'production' -AsHashtable

            $result.metadata.namespace | Should -Be 'production'
        }

        It 'Includes namespace: default when explicitly passed' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ key = 'value' } -Namespace 'default' -AsHashtable

            $result.metadata.namespace | Should -Be 'default'
        }
    }

    Context 'Generic secret output' -Tag 'Generic' {
        It 'Returns YAML string by default' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ foo = 'bar' }

            $result | Should -BeOfType [string]
            $result | Should -Match 'kind: Secret'
            $result | Should -Match 'foo: bar'
        }

        It 'Returns hashtable when -AsHashtable is specified' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ foo = 'bar' } -AsHashtable

            $result | Should -BeOfType [hashtable]
            $result.kind | Should -Be 'Secret'
            $result.metadata.name | Should -Be 'test-secret'
            $result.stringData.foo | Should -Be 'bar'
        }

        It 'Uses stringData (plain text) not base64-encoded data field' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ mykey = 'myvalue' } -AsHashtable

            $result.ContainsKey('stringData') | Should -Be $true
            $result.ContainsKey('data') | Should -Be $false
            $result.stringData.mykey | Should -Be 'myvalue'
        }

        It 'Returns JSON string when -AsJson is specified' -Skip:(-not $script:KubectlAvailable) {
            $result = New-KubernetesSecret -Name 'test-secret' -FromLiteral @{ foo = 'bar' } -AsJson

            $result | Should -BeOfType [string]
            $parsed = $result | ConvertFrom-Json
            $parsed.kind | Should -Be 'Secret'
        }
    }
}
