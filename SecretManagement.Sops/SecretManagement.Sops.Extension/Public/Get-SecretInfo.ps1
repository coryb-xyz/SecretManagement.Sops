function Get-SecretInfo {
    <#
    .SYNOPSIS
    Retrieves metadata about secrets in the SOPS vault.

    .DESCRIPTION
    Lists all available secrets in the vault with their metadata. Supports filtering by
    wildcard pattern to narrow results. Returns SecretInformation objects containing
    the secret name, type, and additional metadata.

    .PARAMETER Filter
    Optional wildcard pattern to filter secrets by name.

    .PARAMETER VaultName
    The name of the registered SecretManagement vault.

    .PARAMETER AdditionalParameters
    Optional vault configuration parameters.

    .OUTPUTS
    Microsoft.PowerShell.SecretManagement.SecretInformation[] - Array of SecretInformation objects.

    .EXAMPLE
    Get-SecretInfo -VaultName 'MySopsVault'

    .EXAMPLE
    Get-SecretInfo -Filter 'db-*' -VaultName 'MySopsVault'

    .EXAMPLE
    Get-SecretInfo -Filter 'apps/prod/*' -VaultName 'MySopsVault'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [hashtable]$AdditionalParameters
    )

    $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters

    # Validate required Path parameter
    Assert-VaultPath -Parameters $params

    # Build the secret index
    $index = Get-SecretIndex -Path $params.Path -FilePattern $params.FilePattern -Recurse $params.Recurse -NamingStrategy $params.NamingStrategy -RequireEncryption $params.RequireEncryption

    $secretInfoList = @()

    foreach ($entry in $index) {
        # Add the main secret entry
        $metadata = @{
            FilePath  = $entry.FilePath
            Namespace = $entry.Namespace
            ShortName = $entry.ShortName
        }

        # Apply filter if provided
        if ($Filter -and ($entry.Name -notlike $Filter)) {
            continue
        }

        # Create SecretInformation object for the secret
        $secretInfo = [Microsoft.PowerShell.SecretManagement.SecretInformation]::new(
            $entry.Name,
            [Microsoft.PowerShell.SecretManagement.SecretType]::Hashtable,
            $VaultName,
            $metadata
        )
        $secretInfoList += $secretInfo
    }

    return $secretInfoList
}
