function Get-SecretIndex {
    <#
    .SYNOPSIS
    Builds an index of all SOPS files in the vault directory.

    .DESCRIPTION
    Scans the vault directory for SOPS files matching the file pattern and
    creates a complete index with metadata for each secret.

    .PARAMETER Path
    The vault directory path.

    .PARAMETER FilePattern
    The file pattern to match (e.g., '*.yaml').

    .PARAMETER Recurse
    Whether to search subdirectories recursively.

    .PARAMETER NamingStrategy
    The naming strategy to use.

    .PARAMETER RequireEncryption
    Filter to only include SOPS-encrypted files. When enabled, files without SOPS
    metadata and files matching unencrypted_suffix patterns from .sops.yaml are excluded.

    .OUTPUTS
    Array - Array of index entries (hashtables).

    .EXAMPLE
    Get-SecretIndex -Path 'C:\secrets' -FilePattern '*.yaml' -Recurse $true

    .EXAMPLE
    Get-SecretIndex -Path 'C:\secrets' -RequireEncryption $true
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path,

        [Parameter()]
        [string]$FilePattern = '*.yaml',

        [Parameter()]
        [bool]$Recurse = $false,

        [Parameter()]
        [string]$NamingStrategy = 'RelativePath',

        [Parameter()]
        [bool]$RequireEncryption = $false
    )

    $index = @()

    # Normalize path to absolute for consistent path resolution
    $absolutePath = [System.IO.Path]::GetFullPath($Path)

    # Find all matching files
    $getChildItemParams = @{
        Path        = $absolutePath
        Filter      = $FilePattern
        File        = $true
        Recurse     = $Recurse
        ErrorAction = 'SilentlyContinue'
    }

    $files = Get-ChildItem @getChildItemParams

    # Apply encryption filtering if requested
    if ($RequireEncryption) {
        # Parse .sops.yaml once for this invocation
        $sopsConfig = Get-SopsConfiguration -VaultPath $absolutePath

        # Filter by suffix exclusions first (cheaper than content check)
        if ($sopsConfig.UnencryptedSuffixes.Count -gt 0) {
            $files = $files | Where-Object {
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                $excluded = $false
                foreach ($suffix in $sopsConfig.UnencryptedSuffixes) {
                    if ($fileName.EndsWith($suffix)) {
                        $excluded = $true
                        break
                    }
                }
                -not $excluded
            }
        }

        # Filter by SOPS metadata presence (streaming state machine)
        $files = $files | Where-Object {
            Test-SopsEncrypted -FilePath $_.FullName
        }
    }

    foreach ($file in $files) {
        # Skip .sops.yaml configuration files
        if ($file.Name -eq '.sops.yaml') {
            continue
        }

        $entry = Get-SecretIndexEntry -FilePath $file.FullName -BasePath $absolutePath -NamingStrategy $NamingStrategy

        if ($null -ne $entry) {
            $index += $entry
        }
    }

    return $index
}
