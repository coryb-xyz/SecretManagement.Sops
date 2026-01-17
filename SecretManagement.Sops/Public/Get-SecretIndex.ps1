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
    [OutputType([object[]])]
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

    $absolutePath = [System.IO.Path]::GetFullPath($Path)

    $getChildItemParams = @{
        Path        = $absolutePath
        Filter      = $FilePattern
        File        = $true
        Recurse     = $Recurse
        ErrorAction = 'SilentlyContinue'
    }

    $files = Get-ChildItem @getChildItemParams | Where-Object { $_.Name -ne '.sops.yaml' }

    if ($RequireEncryption) {
        $sopsConfig = Get-SopsConfiguration -VaultPath $absolutePath
        $unencryptedSuffixes = $sopsConfig.UnencryptedSuffixes

        $files = $files | Where-Object {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)

            $hasSuffixMatch = $false
            foreach ($suffix in $unencryptedSuffixes) {
                if ($fileName.EndsWith($suffix)) {
                    $hasSuffixMatch = $true
                    break
                }
            }

            (-not $hasSuffixMatch) -and (Test-SopsEncrypted -FilePath $_.FullName)
        }
    }

    $index = @(
        foreach ($file in $files) {
            $entry = Get-SecretIndexEntry -FilePath $file.FullName -BasePath $absolutePath -NamingStrategy $NamingStrategy
            if ($null -ne $entry) {
                $entry
            }
        }
    )

    return $index
}
