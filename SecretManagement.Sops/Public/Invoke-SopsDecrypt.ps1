function Invoke-SopsDecrypt {
    <#
    .SYNOPSIS
    Wrapper for SOPS decryption operations.

    .DESCRIPTION
    Decrypts a SOPS-encrypted file and optionally extracts a specific key using JSONPath.

    .PARAMETER FilePath
    The path to the SOPS-encrypted file to decrypt.

    .PARAMETER Extract
    Optional JSONPath expression to extract a specific value from the decrypted content.

    .OUTPUTS
    String - The decrypted content or extracted value.

    .EXAMPLE
    Invoke-SopsDecrypt -FilePath 'C:\secrets\db.yaml'

    .EXAMPLE
    Invoke-SopsDecrypt -FilePath 'C:\secrets\config.yaml' -Extract '["database"]["password"]'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Extract,

        [Parameter()]
        [hashtable]$VaultParameters
    )

    if (-not (Test-SopsAvailable)) {
        throw "SOPS binary not found in PATH. Please install SOPS from https://github.com/getsops/sops/releases"
    }

    $sopsArgs = @('--decrypt')

    if ($Extract) {
        $sopsArgs += '--extract', $Extract
    }

    $sopsArgs += $FilePath

    # Determine if we need to scope environment variables for this operation
    if ($VaultParameters) {
        $sopsEnv = Get-SopsEnvironment -VaultParameters $VaultParameters

        if ($sopsEnv.Count -gt 0) {
            # Execute with scoped environment variables
            $output = Invoke-WithScopedEnv -EnvVars $sopsEnv -ScriptBlock {
                & sops @sopsArgs 2>&1
            }
        }
        else {
            # No environment override needed - use existing environment
            $output = & sops @sopsArgs 2>&1
        }
    }
    else {
        # Backward compatibility: no VaultParameters provided
        $output = & sops @sopsArgs 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        $errorMessage = $output -join "`n"
        $formattedError = Format-SopsError -ErrorMessage $errorMessage -Operation 'decrypt' -VaultParameters $VaultParameters
        throw $formattedError
    }

    return ($output -join "`n")
}
