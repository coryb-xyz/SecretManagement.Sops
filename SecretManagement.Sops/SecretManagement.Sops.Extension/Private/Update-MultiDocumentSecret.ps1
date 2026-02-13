function Set-HashtableValueAtPath {
    <#
    .SYNOPSIS
    Sets or removes a value in a hashtable at a SOPS JSONPath location.

    .DESCRIPTION
    Navigates a hashtable using SOPS JSONPath segments and sets or removes the value
    at the leaf key. Creates intermediate hashtables as needed for new paths.

    .PARAMETER Hashtable
    The hashtable to modify.

    .PARAMETER SopsPath
    A SOPS JSONPath expression (e.g., '["stringData"]["password"]').

    .PARAMETER Value
    The value to set. If $null, the key is removed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Hashtable,

        [Parameter(Mandatory)]
        [string]$SopsPath,

        [Parameter()]
        [AllowNull()]
        $Value
    )

    $segments = @([regex]::Matches($SopsPath, '\["([^"]+)"\]') | ForEach-Object { $_.Groups[1].Value })

    if ($segments.Count -eq 0) {
        throw "Invalid SOPS path: $SopsPath"
    }

    $current = $Hashtable
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        $key = $segments[$i]
        if (-not $current.ContainsKey($key)) {
            $current[$key] = @{}
        }
        $current = $current[$key]
    }

    $leafKey = $segments[-1]
    if ($null -eq $Value) {
        if ($current.ContainsKey($leafKey)) {
            $current.Remove($leafKey)
        }
    }
    else {
        $current[$leafKey] = $Value
    }
}

function Test-DocumentNameMatch {
    <#
    .SYNOPSIS
    Checks whether any parsed YAML document has the given metadata.name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]]$ParsedDocuments,

        [Parameter(Mandatory)]
        [string]$Name
    )

    # Use Contains() not ContainsKey() to support both Hashtable and OrderedDictionary.
    foreach ($doc in $ParsedDocuments) {
        if ($doc -is [System.Collections.IDictionary] -and
            $doc.Contains('metadata') -and
            $doc['metadata'] -is [System.Collections.IDictionary] -and
            $doc['metadata'].Contains('name') -and
            $doc['metadata']['name'] -eq $Name) {
            return $true
        }
    }
    return $false
}

function Update-MultiDocumentSecret {
    <#
    .SYNOPSIS
    Updates a specific document within a multi-document SOPS-encrypted YAML file.

    .DESCRIPTION
    Uses a decrypt-modify-reencrypt workflow for multi-document YAML files.
    Decrypts the full file, identifies the target document, modifies it in memory,
    reassembles all documents, and re-encrypts the file.

    .PARAMETER FilePath
    Path to the multi-document encrypted YAML file.

    .PARAMETER SetPaths
    Array of hashtables with Path and Value properties for set/unset operations.

    .PARAMETER VaultParameters
    Vault configuration parameters (must include Path for encryption rules).

    .PARAMETER SecretName
    The name of the secret (used for error messages).

    .PARAMETER DocumentName
    Optional. Target document by metadata.name instead of auto-detecting.

    .PARAMETER AppendIfNotFound
    When specified alongside DocumentName, appends a new document (reconstructed from
    SetPaths) if no existing document matches DocumentName. Without this switch the
    function throws an error when DocumentName is not found (existing behavior).

    .OUTPUTS
    None. Throws errors on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [hashtable[]]$SetPaths,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters,

        [Parameter(Mandatory)]
        [string]$SecretName,

        [Parameter()]
        [string]$DocumentName,

        [Parameter()]
        [switch]$AppendIfNotFound
    )

    # Decrypt and split into individual documents
    $plaintext = Invoke-SopsDecrypt -FilePath $FilePath -VaultParameters $VaultParameters
    $plaintextDocs = Split-YamlDocuments -Content $plaintext

    Import-Module powershell-yaml -ErrorAction Stop
    $parsedDocs = @(foreach ($doc in $plaintextDocs) {
        $doc | ConvertFrom-Yaml
    })

    # Determine whether to append a new document or modify an existing one.
    $shouldAppend = $AppendIfNotFound -and
        -not [string]::IsNullOrEmpty($DocumentName) -and
        -not (Test-DocumentNameMatch -ParsedDocuments $parsedDocs -Name $DocumentName)

    if ($shouldAppend) {
        $newDoc = @{}
        foreach ($item in $SetPaths) {
            Set-HashtableValueAtPath -Hashtable $newDoc -SopsPath $item.Path -Value $item.Value
        }
        $newDocYaml = ($newDoc | ConvertTo-Yaml).TrimEnd("`r", "`n")
        $plaintextDocs = @($plaintextDocs) + @($newDocYaml)
    }
    else {
        $targetIndex = Find-TargetDocumentIndex -ParsedDocuments $parsedDocs -SetPaths $SetPaths -DocumentName $DocumentName

        foreach ($item in $SetPaths) {
            Set-HashtableValueAtPath -Hashtable $parsedDocs[$targetIndex] -SopsPath $item.Path -Value $item.Value
        }

        $modifiedYaml = ($parsedDocs[$targetIndex] | ConvertTo-Yaml).TrimEnd("`r", "`n")
        $plaintextDocs[$targetIndex] = $modifiedYaml
    }

    # Reassemble and re-encrypt from vault root so SOPS path_regex rules match
    $reassembled = $plaintextDocs -join "`n---`n"
    Set-Content -Path $FilePath -Value $reassembled -NoNewline
    $relativePath = [System.IO.Path]::GetRelativePath($VaultParameters.Path, $FilePath)

    $previousLocation = Get-Location
    try {
        Set-Location -Path $VaultParameters.Path
        Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $VaultParameters
    }
    catch {
        throw "Failed to re-encrypt multi-document secret '$SecretName': $_"
    }
    finally {
        Set-Location -Path $previousLocation
    }
}
