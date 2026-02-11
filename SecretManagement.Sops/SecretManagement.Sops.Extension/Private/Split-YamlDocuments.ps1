function Split-YamlDocuments {
    <#
    .SYNOPSIS
    Splits a multi-document YAML string into individual documents.

    .DESCRIPTION
    Splits YAML content at document separator lines (---) into an array of
    individual document strings. Safe against SOPS encrypted content where
    AGE encrypted blocks contain dashes but are always indented.

    .PARAMETER Content
    The YAML string to split, potentially containing multiple documents.

    .OUTPUTS
    String array of individual YAML documents (without separator lines).

    .EXAMPLE
    $docs = Split-YamlDocuments -Content "doc1: val1`n---`ndoc2: val2"
    # Returns @("doc1: val1", "doc2: val2")
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $documents = [System.Collections.Generic.List[string]]::new()
    $currentLines = [System.Collections.Generic.List[string]]::new()
    $lines = $Content -split '\r?\n'
    $seenContent = $false

    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            if (-not $seenContent) {
                # Skip leading --- (YAML document start marker)
                continue
            }

            if ($currentLines.Count -gt 0) {
                $documents.Add(($currentLines -join "`n"))
                $currentLines.Clear()
            }
        }
        else {
            $currentLines.Add($line)
            $seenContent = $true
        }
    }

    if ($currentLines.Count -gt 0) {
        $documents.Add(($currentLines -join "`n"))
    }

    return $documents.ToArray()
}
