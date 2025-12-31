function Invoke-SopsSet {
    <#
    .SYNOPSIS
    Wrapper for SOPS --set operations.

    .DESCRIPTION
    Updates a specific value in a SOPS-encrypted file without fully decrypting and re-encrypting it.
    Useful for changing individual keys in complex YAML/JSON structures.

    .PARAMETER SetExpression
    The SOPS set expression (e.g., '["database"]["password"] "newvalue"').

    .PARAMETER FilePath
    The path to the SOPS-encrypted file to modify.

    .PARAMETER VaultParameters
    Optional vault parameters that may include AgeKeyFile for per-vault key configuration.

    .OUTPUTS
    String array - The output from the SOPS command.

    .EXAMPLE
    Invoke-SopsSet -SetExpression '["password"] "newpass"' -FilePath 'C:\secrets\db.yaml'

    .EXAMPLE
    $params = @{ AgeKeyFile = 'C:\keys\vault.txt' }
    Invoke-SopsSet -SetExpression '["apikey"] "abc123"' -FilePath 'C:\secrets\api.yaml' -VaultParameters $params

    .NOTES
    Throws an exception if the SOPS --set command fails.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SetExpression,

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
                & sops --set $SetExpression $FilePath 2>&1
            }
        }
        else {
            # No environment override needed - use existing environment
            $output = & sops --set $SetExpression $FilePath 2>&1
        }
    }
    else {
        # Backward compatibility: no VaultParameters provided
        $output = & sops --set $SetExpression $FilePath 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        $errorMsg = $output -join "`n"
        $formattedError = Format-SopsError -ErrorMessage $errorMsg -Operation 'set' -VaultParameters $VaultParameters
        throw $formattedError
    }

    return $output
}
