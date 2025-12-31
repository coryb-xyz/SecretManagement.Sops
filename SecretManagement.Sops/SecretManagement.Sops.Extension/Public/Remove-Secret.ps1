function Remove-Secret {
    <#
    .SYNOPSIS
    Removes a secret file from the SOPS vault.

    .DESCRIPTION
    Deletes an entire SOPS-encrypted secret file from the vault.

    To remove individual keys from a structured secret (e.g., Kubernetes Secret),
    use Set-Secret with path syntax instead:
        ".stringData.keyname: null" | Set-Secret -Name secretname -Vault vaultname

    .PARAMETER Name
    The name of the secret to remove. Can include namespace path.

    .PARAMETER VaultName
    The name of the registered vault.

    .PARAMETER AdditionalParameters
    Additional vault parameters (Path, FilePattern, etc.).

    .OUTPUTS
    None. This function does not return output.

    .EXAMPLE
    Remove-Secret -Name 'db-password' -Vault 'MySopsVault'
    # Removes the entire db-password.yaml file

    .EXAMPLE
    Remove-Secret -Name 'apps/prod/config' -Vault 'MySopsVault'
    # Removes apps/prod/config.yaml file

    .EXAMPLE
    # To remove individual keys, use Set-Secret instead:
    ".stringData.obsolete-key: null" | Set-Secret -Name 'k8s-secret' -Vault 'MySopsVault'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [hashtable]$AdditionalParameters
    )

    # 1. Get and validate vault parameters
    try {
        $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters
        Assert-VaultPath -Parameters $params
    }
    catch {
        throw "Vault configuration error: $_"
    }

    # 2. Resolve secret name to file path
    $resolution = Resolve-SecretEntry -Name $Name -VaultParameters $params
    $secretEntry = $resolution.Entry
    $filePath = $secretEntry.FilePath

    # 3. Remove entire secret file
    if (-not (Test-Path $filePath)) {
        throw "Secret file not found: $filePath"
    }

    try {
        Remove-Item -Path $filePath -Force
        # Success - no return value needed
    }
    catch {
        throw "Failed to remove secret file '$filePath': $_"
    }
}
