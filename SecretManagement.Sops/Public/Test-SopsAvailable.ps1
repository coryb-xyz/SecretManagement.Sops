function Test-SopsAvailable {
    <#
    .SYNOPSIS
    Tests if the SOPS binary is available in the system PATH.

    .DESCRIPTION
    Checks for the presence of the 'sops' executable by attempting to run 'sops --version'.

    .OUTPUTS
    Boolean - Returns $true if SOPS is available, $false otherwise.

    .EXAMPLE
    if (Test-SopsAvailable) {
        Invoke-SopsEncrypt -FilePath './secret.yaml' -InPlace
    }
    else {
        Write-Warning "SOPS is not installed. Install from https://github.com/getsops/sops/releases"
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $null = Get-Command 'sops' -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}
