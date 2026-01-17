function Test-PathMatchesRegex {
    <#
    .SYNOPSIS
    Tests if a file path matches a SOPS path_regex pattern.

    .DESCRIPTION
    Checks if a file path matches the given regex pattern from a SOPS creation_rule.
    Handles cross-platform path separators by normalizing paths to forward slashes
    before matching against the regex.

    The function:
    1. Converts file path to relative path from vault root
    2. Normalizes backslashes to forward slashes
    3. Tests against the provided regex pattern

    .PARAMETER FilePath
    The absolute or relative path to the file to test.

    .PARAMETER VaultPath
    The vault root directory path.

    .PARAMETER PathRegex
    The regex pattern from the SOPS creation_rule path_regex field.

    .OUTPUTS
    Boolean indicating whether the path matches the regex.

    .EXAMPLE
    Test-PathMatchesRegex -FilePath 'C:\vault\migration\k8s.yaml' `
        -VaultPath 'C:\vault' `
        -PathRegex 'migration[/\\].*\.yaml$'
    # Returns: $true

    .EXAMPLE
    Test-PathMatchesRegex -FilePath 'apps/web/config.yaml' `
        -VaultPath '/vault' `
        -PathRegex 'apps[/\\]web[/\\].*\.yaml$'
    # Returns: $true

    .NOTES
    Uses [System.IO.Path]::GetRelativePath for accurate path resolution.
    Normalizes paths to forward slashes to match SOPS convention.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$VaultPath,

        [Parameter(Mandatory)]
        [string]$PathRegex
    )

    # Get absolute paths for accurate comparison
    $absoluteFilePath = [System.IO.Path]::GetFullPath($FilePath)
    $absoluteVaultPath = [System.IO.Path]::GetFullPath($VaultPath)

    # Get relative path from vault root (SOPS matches against relative paths)
    $relativePath = [System.IO.Path]::GetRelativePath($absoluteVaultPath, $absoluteFilePath)

    # Normalize to forward slashes for regex matching (SOPS convention)
    $normalizedPath = $relativePath -replace '\\', '/'

    # Test against regex
    $normalizedPath -match $PathRegex
}
