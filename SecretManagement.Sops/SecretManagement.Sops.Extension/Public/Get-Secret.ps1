function Get-Secret {
    <#
    .SYNOPSIS
    Retrieves a secret from the SOPS vault.

    .DESCRIPTION
    Retrieves and decrypts a secret from the SOPS vault. Returns the secret value
    as a PowerShell object (string, hashtable, array, etc.) based on the encrypted
    file's content.

    .PARAMETER Name
    The name of the secret to retrieve.

    .PARAMETER VaultName
    The name of the registered SecretManagement vault.

    .PARAMETER AdditionalParameters
    Optional vault configuration parameters.

    .OUTPUTS
    Object - The decrypted secret value as a PowerShell object.

    .EXAMPLE
    Get-Secret -Name 'db-password' -VaultName 'MySopsVault'

    .EXAMPLE
    Get-Secret -Name 'apps/prod/config' -VaultName 'MySopsVault'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [hashtable]$AdditionalParameters
    )

    $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters

    # Validate required Path parameter
    Assert-VaultPath -Parameters $params

    # Resolve secret name to index entry
    try {
        $resolution = Resolve-SecretEntry -Name $Name -VaultParameters $params
    }
    catch {
        # Resolve-SecretEntry throws on Collision - re-throw
        # For NotFound, it also throws, but we want to return $null per SecretManagement convention
        if ($_.Exception.Message -match "Secret.*not found") {
            return $null
        }
        throw
    }

    $secretEntry = $resolution.Entry

    # Decrypt and parse YAML to typed objects
    try {
        $decryptedYaml = Invoke-SopsDecrypt -FilePath $secretEntry.FilePath -VaultParameters $params

        # Verify we got content
        if ([string]::IsNullOrWhiteSpace($decryptedYaml)) {
            Write-Warning "No content returned from decrypting secret '$Name'"
            return $null
        }

        # Convert from YAML to typed PowerShell object
        $typedSecret = ConvertFrom-SecretYaml -YamlContent $decryptedYaml

        # Use Write-Output -NoEnumerate for arrays to prevent unwrapping
        if ($typedSecret -is [array]) {
            return (Write-Output -NoEnumerate $typedSecret)
        }
        return $typedSecret
    }
    catch {
        throw "Failed to decrypt secret '$Name': $_"
    }
}
