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
    Assert-VaultPath -Parameters $params

    # Resolve secret - return $null for NotFound per SecretManagement convention
    try {
        $resolution = Resolve-SecretEntry -Name $Name -VaultParameters $params
    }
    catch {
        if ($_.Exception.Message -match "Secret.*not found") {
            return $null
        }
        throw
    }

    # Decrypt the secret file
    try {
        $decryptedYaml = Invoke-SopsDecrypt -FilePath $resolution.Entry.FilePath -VaultParameters $params
    }
    catch {
        throw "Failed to decrypt secret '$Name': $_"
    }

    if ([string]::IsNullOrWhiteSpace($decryptedYaml)) {
        Write-Warning "No content returned from decrypting secret '$Name'"
        return $null
    }

    # Use Write-Output -NoEnumerate to prevent array unwrapping
    Write-Output -NoEnumerate $decryptedYaml
}
