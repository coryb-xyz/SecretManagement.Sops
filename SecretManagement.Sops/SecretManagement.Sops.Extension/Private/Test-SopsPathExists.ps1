function Test-SopsPathExists {
    <#
    .SYNOPSIS
    Checks if a SOPS JSONPath exists in a parsed YAML document.

    .DESCRIPTION
    Given a SOPS JSONPath expression like '["stringData"]["password"]' and a parsed
    YAML hashtable, walks the hashtable to check if the full path exists.

    .PARAMETER SopsPath
    A SOPS JSONPath expression (e.g., '["stringData"]["password"]').

    .PARAMETER ParsedDocument
    A hashtable or OrderedDictionary from ConvertFrom-Yaml.

    .OUTPUTS
    Boolean indicating whether the path exists in the document.

    .EXAMPLE
    $doc = @{ stringData = @{ password = "secret" } }
    Test-SopsPathExists -SopsPath '["stringData"]["password"]' -ParsedDocument $doc
    # Returns $true
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SopsPath,

        [Parameter(Mandatory)]
        [object]$ParsedDocument
    )

    # Extract key segments from SOPS JSONPath: ["key1"]["key2"] → @("key1", "key2")
    $segments = [regex]::Matches($SopsPath, '\["([^"]+)"\]') | ForEach-Object { $_.Groups[1].Value }

    if ($segments.Count -eq 0) {
        return $false
    }

    $current = $ParsedDocument
    foreach ($segment in $segments) {
        if ($current -isnot [System.Collections.IDictionary]) {
            return $false
        }

        if (-not $current.ContainsKey($segment)) {
            return $false
        }
        $current = $current[$segment]
    }

    return $true
}
