function Test-SopsPathMatch {
    <#
    .SYNOPSIS
    Tests if a file path matches any SOPS creation rule's path_regex.

    .DESCRIPTION
    Determines if a file path matches any creation rule's path_regex pattern.
    Uses relative path from vault root and normalizes path separators for
    cross-platform consistency.

    Returns first matching rule (SOPS uses first-match semantics).

    .PARAMETER FilePath
    Absolute path to the file.

    .PARAMETER VaultPath
    Vault root directory (used for relative path calculation).

    .PARAMETER CreationRules
    Array of parsed creation rules from Get-SopsConfiguration.

    .OUTPUTS
    Hashtable with keys:
    - Matched: Boolean indicating if path matched any rule
    - MatchedRule: The first matching rule hashtable (or $null)

    .EXAMPLE
    $match = Test-SopsPathMatch -FilePath 'C:\vault\apps\prod\secret.yaml' -VaultPath 'C:\vault' -CreationRules $rules
    if ($match.Matched) {
        Write-Host "Matched rule with path_regex: $($match.MatchedRule.PathRegex)"
    }

    .NOTES
    Path separators are normalized to forward slashes for regex matching.
    Invalid regex patterns are handled gracefully with warnings.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$VaultPath,

        [Parameter(Mandatory)]
        [array]$CreationRules
    )

    # Calculate relative path from vault root
    # Use forward slashes for cross-platform consistency (matches SOPS behavior)
    $relativePath = [System.IO.Path]::GetRelativePath($VaultPath, $FilePath)
    $relativePath = $relativePath -replace '\\', '/'

    foreach ($rule in $CreationRules) {
        if (-not $rule.PathRegex) {
            continue
        }

        try {
            if ($relativePath -match $rule.PathRegex) {
                return @{
                    Matched     = $true
                    MatchedRule = $rule
                }
            }
        }
        catch {
            Write-Warning "Invalid regex in path_regex '$($rule.PathRegex)': $_"
            continue
        }
    }

    return @{
        Matched     = $false
        MatchedRule = $null
    }
}
