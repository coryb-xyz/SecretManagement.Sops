function Test-YamlLikeString {
    <#
    .SYNOPSIS
    Detects if a string appears to be multi-line YAML content.

    .DESCRIPTION
    Uses heuristics to determine if a string should be treated as YAML for parsing.
    This prevents false positives on simple passwords or connection strings.

    Detection criteria:
    - Must contain newlines (multi-line)
    - Must have YAML key:value patterns (e.g., "key:", "  key:")

    .PARAMETER InputString
    The string to test for YAML-like patterns.

    .OUTPUTS
    Boolean - $true if the string appears to be YAML, $false otherwise.

    .EXAMPLE
    Test-YamlLikeString -InputString "apiVersion: v1`nkind: Secret"
    # Returns: $true

    .EXAMPLE
    Test-YamlLikeString -InputString "simple-password-123"
    # Returns: $false

    .EXAMPLE
    Test-YamlLikeString -InputString "postgresql://user:pass@host:5432/db"
    # Returns: $false (single line, even with colons)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$InputString
    )

    # Empty string is not YAML
    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return $false
    }

    # Must be multi-line to be considered YAML
    # Single-line strings are treated as plain values (passwords, URLs, etc.)
    if ($InputString -notmatch "`n") {
        return $false
    }

    # Check for YAML key:value patterns
    # Pattern 1: Key at start of line (e.g., "apiVersion: v1")
    if ($InputString -match "^[a-zA-Z][a-zA-Z0-9_-]*:\s*") {
        return $true
    }

    # Pattern 2: Indented key (e.g., "  metadata:")
    if ($InputString -match "`n\s+[a-zA-Z][a-zA-Z0-9_-]*:\s*") {
        return $true
    }

    # No YAML patterns detected
    return $false
}
