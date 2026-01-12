function Invoke-SopsCommand {
    <#
    .SYNOPSIS
    Internal helper to invoke SOPS commands with environment scoping and error handling.

    .DESCRIPTION
    Provides a centralized way to invoke SOPS commands with:
    - Automatic environment variable scoping (SOPS_AGE_KEY_FILE, etc.)
    - Consistent error handling with Format-SopsError
    - Exit code checking

    This function consolidates the common pattern used across all Invoke-Sops* functions.

    .PARAMETER SopsArgs
    Array of arguments to pass to the sops command.

    .PARAMETER VaultParameters
    Optional hashtable of vault parameters for environment variable scoping.

    .PARAMETER Operation
    The operation being performed (e.g., 'decrypt', 'encrypt', 'set', 'unset').
    Used for error message formatting.

    .OUTPUTS
    String - The output from the SOPS command.

    .EXAMPLE
    $output = Invoke-SopsCommand -SopsArgs @('-d', 'file.yaml') -VaultParameters $params -Operation 'decrypt'

    .NOTES
    This is an internal helper function used by Invoke-SopsDecrypt, Invoke-SopsEncrypt,
    Invoke-SopsSet, and Invoke-SopsUnset to reduce code duplication.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SopsArgs,

        [Parameter()]
        [hashtable]$VaultParameters,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    # Determine if we need to scope environment variables for this operation
    if ($VaultParameters) {
        $sopsEnv = Get-SopsEnvironment -VaultParameters $VaultParameters

        if ($sopsEnv.Count -gt 0) {
            # Execute with scoped environment variables
            $output = Invoke-WithScopedEnv -EnvVars $sopsEnv -ScriptBlock {
                & sops @SopsArgs 2>&1
            }
        }
        else {
            # No environment override needed - use existing environment
            $output = & sops @SopsArgs 2>&1
        }
    }
    else {
        # Backward compatibility: no VaultParameters provided
        $output = & sops @SopsArgs 2>&1
    }

    # Check exit code and provide formatted error if command failed
    if ($LASTEXITCODE -ne 0) {
        $errorMessage = $output -join "`n"
        $formattedError = Format-SopsError -ErrorMessage $errorMessage -Operation $Operation -VaultParameters $VaultParameters
        throw $formattedError
    }

    return ($output -join "`n")
}
