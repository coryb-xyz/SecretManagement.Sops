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

    .PARAMETER RequireSopsMatch
    Filter to only include files that match .sops.yaml creation rules but are not yet
    encrypted. Useful for identifying files that need encryption during GitOps migration.

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
        [bool]$RequireEncryption = $false,

        [Parameter()]
        [bool]$RequireSopsMatch = $false
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
    if ($RequireEncryption -or $RequireSopsMatch) {
        # Parse .sops.yaml once for this invocation
        $sopsConfig = Get-SopsConfiguration -VaultPath $absolutePath

        # PHASE 1: Suffix-based pre-filtering (cheap)
        if ($RequireEncryption -and $sopsConfig.UnencryptedSuffixes.Count -gt 0) {
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

        # PHASE 2: Content-based filtering
        if ($RequireEncryption) {
            # Filter to ONLY SOPS-encrypted files
            $files = $files | Where-Object {
                Test-SopsEncrypted -FilePath $_.FullName
            }
        }
        elseif ($RequireSopsMatch) {
            # Filter to files matching .sops.yaml rules but NOT encrypted
            if ($sopsConfig.CreationRules.Count -gt 0) {
                $files = $files | Where-Object {
                    # Must NOT be encrypted
                    $isEncrypted = Test-SopsEncrypted -FilePath $_.FullName
                    if ($isEncrypted) {
                        return $false
                    }

                    # Must match a creation rule's path_regex
                    $pathMatch = Test-SopsPathMatch -FilePath $_.FullName -VaultPath $absolutePath -CreationRules $sopsConfig.CreationRules
                    if (-not $pathMatch.Matched) {
                        return $false
                    }

                    # Must contain encryptable content
                    $contentMatch = Test-SopsContentMatch -FilePath $_.FullName -CreationRule $pathMatch.MatchedRule
                    return $contentMatch
                }
            }
            else {
                # No .sops.yaml rules - no files match
                $files = @()
            }
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
