function Test-SecretVault {
    <#
    .SYNOPSIS
    Validates the SOPS vault configuration.

    .DESCRIPTION
    Checks that the vault is properly configured, the SOPS binary is available,
    and the vault path is accessible. Returns $true if the vault is valid and
    ready to use, $false otherwise.

    .PARAMETER VaultName
    The name of the registered SecretManagement vault.

    .PARAMETER AdditionalParameters
    Optional vault configuration parameters.

    .OUTPUTS
    Boolean - Returns $true if vault is valid, $false otherwise.

    .EXAMPLE
    if (Test-SecretVault -VaultName 'MySopsVault') {
        Write-Host "Vault is ready to use"
    }

    .EXAMPLE
    Test-SecretVault -VaultName 'MySopsVault' -AdditionalParameters @{ Path = 'C:\secrets' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [hashtable]$AdditionalParameters
    )

    try {
        $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters

        # Validate vault path
        try {
            Assert-VaultPath -Parameters $params
        }
        catch {
            Write-Error $_.Exception.Message
            return $false
        }

        # Check that SOPS binary is available
        if (-not (Test-SopsAvailable)) {
            Write-Error "SOPS binary not found in PATH. Install from https://github.com/getsops/sops/releases"
            return $false
        }

        # Try to build the index (this validates file access)
        try {
            $index = Get-SecretIndex -Path $params.Path -FilePattern $params.FilePattern -Recurse $params.Recurse -NamingStrategy $params.NamingStrategy

            if ($index.Count -eq 0) {
                Write-Warning "No SOPS files found matching pattern '$($params.FilePattern)' in path '$($params.Path)'"
            }
        }
        catch {
            Write-Error "Failed to index vault: $_"
            return $false
        }

        return $true
    }
    catch {
        Write-Error "Vault validation failed: $_"
        return $false
    }
}
