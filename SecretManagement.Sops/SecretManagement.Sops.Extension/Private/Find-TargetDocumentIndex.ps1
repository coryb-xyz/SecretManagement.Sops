function Get-DocumentMetadataName {
    <#
    .SYNOPSIS
    Safely extracts metadata.name from a parsed YAML document.
    Returns $null when the document structure does not contain the key.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Document
    )

    if ($Document -isnot [System.Collections.IDictionary] -or -not $Document.Contains('metadata')) {
        return $null
    }

    $metadata = $Document['metadata']
    if ($metadata -isnot [System.Collections.IDictionary] -or -not $metadata.Contains('name')) {
        return $null
    }

    return $metadata['name']
}

function Format-DocumentList {
    <#
    .SYNOPSIS
    Formats document index/name pairs for error messages.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Documents
    )

    ($Documents | ForEach-Object {
        if ($_.Name) { "  [$($_.Index)] metadata.name='$($_.Name)'" }
        else { "  [$($_.Index)] (no metadata.name)" }
    }) -join "`n"
}

function Find-TargetDocumentIndex {
    <#
    .SYNOPSIS
    Determines which document in a multi-document YAML file should be updated.

    .DESCRIPTION
    Finds the target document index using either explicit targeting (by metadata.name)
    or auto-detection (by key path existence). Returns a 0-based index.

    .PARAMETER ParsedDocuments
    Array of parsed YAML documents (hashtables from ConvertFrom-Yaml).

    .PARAMETER SetPaths
    Array of hashtables with Path and Value properties (from ConvertTo-SopsSetPath).

    .PARAMETER DocumentName
    Optional. If specified, targets the document where metadata.name matches this value.

    .OUTPUTS
    Int - 0-based index of the target document.

    .EXAMPLE
    $index = Find-TargetDocumentIndex -ParsedDocuments $docs -SetPaths $paths
    # Auto-detects by key path existence

    .EXAMPLE
    $index = Find-TargetDocumentIndex -ParsedDocuments $docs -SetPaths $paths -DocumentName 'api-keys'
    # Targets document where metadata.name is 'api-keys'
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [object[]]$ParsedDocuments,

        [Parameter(Mandatory)]
        [hashtable[]]$SetPaths,

        [Parameter()]
        [string]$DocumentName
    )

    $docNames = for ($i = 0; $i -lt $ParsedDocuments.Count; $i++) {
        [PSCustomObject]@{
            Index = $i
            Name  = Get-DocumentMetadataName -Document $ParsedDocuments[$i]
        }
    }

    # Mode 1: Explicit targeting by DocumentName
    if (-not [string]::IsNullOrEmpty($DocumentName)) {
        $matches = @($docNames | Where-Object { $_.Name -eq $DocumentName })

        if ($matches.Count -eq 0) {
            $available = Format-DocumentList -Documents $docNames
            throw "No document found with metadata.name '$DocumentName'. Available documents:`n$available"
        }

        if ($matches.Count -gt 1) {
            throw "Multiple documents found with metadata.name '$DocumentName'. This should not happen in a valid multi-document YAML file."
        }

        return $matches[0].Index
    }

    # Mode 2: Auto-detect by key path existence
    $matchingIndices = @(for ($i = 0; $i -lt $ParsedDocuments.Count; $i++) {
        $doc = $ParsedDocuments[$i]
        $missingPath = $SetPaths | Where-Object {
            -not (Test-SopsPathExists -SopsPath $_.Path -ParsedDocument $doc)
        } | Select-Object -First 1

        if (-not $missingPath) { $i }
    })

    if ($matchingIndices.Count -eq 0) {
        $pathList = ($SetPaths | ForEach-Object { "  $($_.Path)" }) -join "`n"
        $available = Format-DocumentList -Documents $docNames
        throw "Key path not found in any document. Paths searched:`n$pathList`nAvailable documents:`n$available`nUse -Metadata @{DocumentName='name'} to target a specific document."
    }

    if ($matchingIndices.Count -gt 1) {
        $matchDocs = $matchingIndices | ForEach-Object { $docNames[$_] }
        $matchList = Format-DocumentList -Documents $matchDocs
        throw "Key path found in multiple documents:`n$matchList`nUse -Metadata @{DocumentName='name'} to disambiguate."
    }

    return $matchingIndices[0]
}
