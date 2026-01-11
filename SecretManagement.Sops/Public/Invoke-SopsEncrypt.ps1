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

    # Use shared helper for environment scoping and error handling
    $output = Invoke-SopsCommand -SopsArgs $sopsArgs -VaultParameters $VaultParameters -Operation 'encrypt'

    if (-not $InPlace) {
        return $output
    }
}
