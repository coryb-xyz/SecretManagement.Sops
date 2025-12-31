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

    $sopsEnv = @{}

    # Check if AgeKeyFile parameter is provided
    if ($VaultParameters.ContainsKey('AgeKeyFile') -and
        -not [string]::IsNullOrWhiteSpace($VaultParameters.AgeKeyFile)) {

        $ageKeyFile = $VaultParameters.AgeKeyFile

        # Convert relative paths to absolute paths
        if (-not [System.IO.Path]::IsPathRooted($ageKeyFile)) {
            $ageKeyFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ageKeyFile)
        }

        # Validate the key file exists
        if (-not (Test-Path -Path $ageKeyFile -PathType Leaf)) {
            throw "Age key file does not exist: $ageKeyFile`nSpecified in vault AgeKeyFile parameter."
        }

        # Set the environment variable for this operation
        $sopsEnv['SOPS_AGE_KEY_FILE'] = $ageKeyFile

        Write-Verbose "Using vault-specific age key file: $ageKeyFile"
    }
    # Note: If AgeKeyFile is not provided, we don't set anything and let SOPS
    # use the existing $env:SOPS_AGE_KEY_FILE or other encryption methods (Azure KV, etc.)

    return $sopsEnv
}
