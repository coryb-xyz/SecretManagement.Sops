function Assert-VaultPath {
    <#
    .SYNOPSIS
    Validates that the vault Path parameter is present and exists.

    .DESCRIPTION
    Shared validation logic for vault path parameter used by Get-Secret, Get-SecretInfo, and Test-SecretVault.
    Throws an error if the Path parameter is missing or does not exist.

    .PARAMETER Parameters
    The vault parameters hashtable.

    .EXAMPLE
    Assert-VaultPath -Parameters $params
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    if (-not $Parameters.ContainsKey('Path')) {
        throw "Vault parameter 'Path' is required. Use Register-SecretVault with -VaultParameters @{ Path = 'C:\secrets' }"
    }

    if (-not (Test-Path $Parameters.Path -PathType Container)) {
        throw "Vault path does not exist: $($Parameters.Path)"
    }
}
