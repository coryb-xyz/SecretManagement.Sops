function Test-SopsEncrypted {
    <#
    .SYNOPSIS
    Detects if a file contains SOPS encryption metadata.

    .DESCRIPTION
    Uses a streaming state machine approach to efficiently detect SOPS-encrypted files
    without loading the entire file into memory or deserializing YAML.

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
    Performance characteristics:
    - Uses System.IO.StreamReader for streaming (no full file load)
    - Early exit when pattern found (typically within 20 lines)
    - Early abandon if pattern not found (after 50 lines past "sops:")
    - Zero memory overhead, minimal GC pressure
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath
    )

    try {
        # Use StreamReader for efficient line-by-line streaming
        $stream = [System.IO.File]::OpenText($FilePath)
        try {
            # State machine variables
            $foundSops = $false
            $linesSinceSops = 0
            $maxLinesAfterSops = 50  # SOPS metadata typically within first 50 lines after "sops:"

            # Read file line by line
            while ($null -ne ($line = $stream.ReadLine())) {
                # State 1: Looking for "sops:" at start of line
                if (-not $foundSops) {
                    if ($line -match '^sops:\s*$') {
                        $foundSops = $true
                        $linesSinceSops = 0
                        # Continue to State 2
                    }
                }
                # State 2: Found "sops:", now looking for indented "version:" within next N lines
                else {
                    $linesSinceSops++

                    # Early exit: Found version field - this is a SOPS file
                    if ($line -match '^\s+version:\s+\d+') {
                        return $true
                    }

                    # Early abandon: Gone too far past "sops:" without finding version
                    # This handles edge cases like fake-sops.yaml
                    if ($linesSinceSops -gt $maxLinesAfterSops) {
                        return $false
                    }
                }
            }

            # End of file reached
            # Either never found "sops:" or found it but no "version:" within range
            return $false
        }
        finally {
            # Always close the stream
            $stream.Close()
        }
    }
    catch {
        Write-Warning "Failed to read file '$FilePath': $_"
        return $false
    }
}
