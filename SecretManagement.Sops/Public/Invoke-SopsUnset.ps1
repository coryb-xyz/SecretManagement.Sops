function Invoke-SopsUnset {
    <#
    .SYNOPSIS
    Wrapper for SOPS unset operations.

    .DESCRIPTION
    Removes a key or branch from a SOPS-encrypted file without fully decrypting and re-encrypting it.
    Useful for deleting specific fields from complex YAML/JSON structures.

    .PARAMETER Path
    The SOPS JSONPath expression to unset (e.g., '["stringData"]["password"]').

    .PARAMETER FilePath
    The path to the SOPS-encrypted file to modify.

    .PARAMETER VaultParameters
    Optional vault parameters that may include AgeKeyFile for per-vault key configuration.

    .OUTPUTS
    String array - The output from the SOPS command.

    .EXAMPLE
    Invoke-SopsUnset -Path '["stringData"]["password"]' -FilePath 'C:\secrets\db.yaml'

    .EXAMPLE
    $params = @{ AgeKeyFile = 'C:\keys\vault.txt' }
    Invoke-SopsUnset -Path '["stringData"]["obsolete-key"]' -FilePath 'C:\secrets\k8s.yaml' -VaultParameters $params

    .NOTES
    Throws an exception if the SOPS unset command fails.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter()]
        [hashtable]$VaultParameters
    )

    if (-not (Test-SopsAvailable)) {
        throw "SOPS binary not found in PATH. Please install SOPS from https://github.com/getsops/sops/releases"
    }

    # Determine if we need to scope environment variables for this operation
    if ($VaultParameters) {
        $sopsEnv = Get-SopsEnvironment -VaultParameters $VaultParameters

        if ($sopsEnv.Count -gt 0) {
            # Execute with scoped environment variables
            $output = Invoke-WithScopedEnv -EnvVars $sopsEnv -ScriptBlock {
                & sops unset $FilePath $Path 2>&1
            }
        }
        else {
            # No environment override needed - use existing environment
            $output = & sops unset $FilePath $Path 2>&1
        }
    }
    else {
        # Backward compatibility: no VaultParameters provided
        $output = & sops unset $FilePath $Path 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        $errorMsg = $output -join "`n"
        $formattedError = Format-SopsError -ErrorMessage $errorMsg -Operation 'unset' -VaultParameters $VaultParameters
        throw $formattedError
    }

    return $output
}
