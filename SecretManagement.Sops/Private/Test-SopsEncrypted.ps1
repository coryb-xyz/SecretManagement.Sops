function Test-SopsEncrypted {
    <#
    .SYNOPSIS
    Detects if a file contains SOPS encryption metadata.

    .DESCRIPTION
    Uses a streaming approach to efficiently detect SOPS-encrypted files without
    loading the entire file into memory or deserializing YAML.

    The function looks for the SOPS metadata pattern:
    - A line containing "sops:" at the start
    - Followed by an indented line containing "version: <number>" within the next 50 lines

    .PARAMETER FilePath
    Path to the file to check.

    .OUTPUTS
    Boolean - $true if file contains SOPS metadata, $false otherwise.

    .EXAMPLE
    Test-SopsEncrypted -FilePath 'C:\secrets\database.yaml'

    .NOTES
    Performance: Uses StreamReader with early exit when pattern found.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::OpenText($FilePath)
        $foundSops = $false
        $linesSinceSops = 0
        $maxLinesAfterSops = 50

        while ($null -ne ($line = $stream.ReadLine())) {
            if (-not $foundSops) {
                if ($line -match '^sops:\s*$') {
                    $foundSops = $true
                }
            }
            else {
                $linesSinceSops++

                if ($line -match '^\s+version:\s+\d+') {
                    return $true
                }

                if ($linesSinceSops -gt $maxLinesAfterSops) {
                    return $false
                }
            }
        }

        return $false
    }
    catch {
        Write-Warning "Failed to read file '$FilePath': $_"
        return $false
    }
    finally {
        if ($stream) {
            $stream.Close()
        }
    }
}
