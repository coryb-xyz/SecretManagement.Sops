function Invoke-SopsEncrypt {
    <#
    .SYNOPSIS
    Wrapper for SOPS encryption operations.

    .DESCRIPTION
    Encrypts a file using SOPS. Can either return encrypted content to stdout
    or modify the file in-place.

    .PARAMETER FilePath
    The path to the file to encrypt.

    .PARAMETER InPlace
    If specified, encrypts the file in-place instead of returning content to stdout.

    .OUTPUTS
    String - The encrypted content (when -InPlace is not specified).

    .EXAMPLE
    Invoke-SopsEncrypt -FilePath 'C:\secrets\db.yaml'

    .EXAMPLE
    Invoke-SopsEncrypt -FilePath 'C:\secrets\config.yaml' -InPlace
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter()]
        [switch]$InPlace,

        [Parameter()]
        [hashtable]$VaultParameters
    )

    if (-not (Test-SopsAvailable)) {
        throw "SOPS binary not found in PATH. Please install SOPS from https://github.com/getsops/sops/releases"
    }

    $sopsArgs = @('--encrypt')

    if ($InPlace) {
        $sopsArgs += '--in-place'
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
        $formattedError = Format-SopsError -ErrorMessage $errorMessage -Operation 'encrypt' -VaultParameters $VaultParameters
        throw $formattedError
    }

    if (-not $InPlace) {
        return ($output -join "`n")
    }
}
