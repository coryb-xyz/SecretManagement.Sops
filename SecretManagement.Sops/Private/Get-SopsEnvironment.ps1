function Get-SopsEnvironment {
    <#
    .SYNOPSIS
    Builds environment variable hashtable for SOPS operations.

    .DESCRIPTION
    Determines the appropriate environment variables for SOPS based on vault parameters.
    Falls back to existing environment variables if no vault parameter is provided.

    This function enables per-vault age key configuration by translating vault parameters
    into environment variables that SOPS can use for encryption/decryption operations.

    .PARAMETER VaultParameters
    The vault parameters hashtable from Get-VaultParameters.

    .OUTPUTS
    Hashtable of environment variables to set for SOPS operations.
    Returns empty hashtable if no age configuration is needed (falls back to existing environment).

    .EXAMPLE
    $env = Get-SopsEnvironment -VaultParameters @{ AgeKeyFile = 'C:\keys\vault.txt' }
    # Returns: @{ SOPS_AGE_KEY_FILE = 'C:\keys\vault.txt' }

    .EXAMPLE
    $env = Get-SopsEnvironment -VaultParameters @{ Path = 'C:\vault' }
    # Returns: @{} (empty - no age key file specified)

    .NOTES
    - Validates that the key file exists before returning it
    - Converts relative paths to absolute paths for reliability
    - Returns empty hashtable if AgeKeyFile is not provided (allows fallback to global env var)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$VaultParameters
    )

    $ageKeyFile = $VaultParameters['AgeKeyFile']

    # If no AgeKeyFile specified, return empty hashtable to use existing environment
    if ([string]::IsNullOrWhiteSpace($ageKeyFile)) {
        return @{}
    }

    # Convert relative paths to absolute paths
    if (-not [System.IO.Path]::IsPathRooted($ageKeyFile)) {
        $ageKeyFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ageKeyFile)
    }

    if (-not (Test-Path -Path $ageKeyFile -PathType Leaf)) {
        throw "Age key file does not exist: $ageKeyFile`nSpecified in vault AgeKeyFile parameter."
    }

    Write-Verbose "Using vault-specific age key file: $ageKeyFile"

    return @{ SOPS_AGE_KEY_FILE = $ageKeyFile }
}
