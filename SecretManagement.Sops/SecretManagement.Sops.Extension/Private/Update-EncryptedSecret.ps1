function Update-EncryptedSecret {
    <#
    .SYNOPSIS
    Updates an existing SOPS-encrypted secret file using patch operations.

    .DESCRIPTION
    Uses SOPS --set and --unset to update specific fields in an existing encrypted
    secret file without decrypting and re-encrypting the entire file. Supports both
    string and hashtable content.

    For string values, intelligently detects the update mode:
    - Path-based syntax (.path.to.field: value)
    - YAML content (multi-line YAML to patch)
    - Plain string (stored in 'value' key)

    .PARAMETER FilePath
    The path to the existing encrypted secret file.

    .PARAMETER Content
    The content to update. Can be a string or hashtable.

    .PARAMETER VaultParameters
    Vault configuration parameters.

    .PARAMETER SecretName
    The name of the secret (used for error messages).

    .PARAMETER Metadata
    Optional metadata hashtable. Supports DocumentName key to target a specific
    document in multi-document YAML files.

    .OUTPUTS
    None. Throws errors on failure.

    .EXAMPLE
    Update-EncryptedSecret -FilePath 'C:\vault\secret.yaml' -Content '.password: newPass' -VaultParameters $params -SecretName 'db'

    .EXAMPLE
    $content = @{ stringData = @{ password = 'newPass' } }
    Update-EncryptedSecret -FilePath 'C:\vault\secret.yaml' -Content $content -VaultParameters $params -SecretName 'api'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [object]$Content,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters,

        [Parameter(Mandatory)]
        [string]$SecretName,

        [Parameter()]
        [hashtable]$Metadata
    )

    # Detect complete K8s-style document (has apiVersion, kind, metadata.name).
    # When found in a multi-document file, use metadata.name for targeting and
    # allow appending if no matching document exists.
    $extractedDocName = $null
    # Use Contains() not ContainsKey(): OrderedDictionary (from [ordered]@{}) only
    # implements IDictionary.Contains(); ContainsKey() exists only on Hashtable.
    if ($Content -is [System.Collections.IDictionary] -and
        $Content.Contains('kind') -and $Content.Contains('apiVersion') -and
        $Content.Contains('metadata') -and $Content['metadata'] -is [System.Collections.IDictionary] -and
        $Content['metadata'].Contains('name')) {
        $extractedDocName = $Content['metadata']['name']
    }

    # Convert content to SOPS set paths based on type
    $setPaths = if ($Content -is [string]) {
        ConvertTo-SopsSetPathFromString -Secret $Content
    }
    else {
        ConvertTo-SopsSetPath -Object $Content
    }

    # Delegate to multi-document handler if file contains document separators
    $fileContent = Get-Content -Path $FilePath -Raw
    if ($fileContent -match '(?m)^---\s*$') {
        $splatParams = @{
            FilePath        = $FilePath
            SetPaths        = $setPaths
            VaultParameters = $VaultParameters
            SecretName      = $SecretName
        }
        if ($Metadata -and $Metadata.ContainsKey('DocumentName')) {
            # Explicit DocumentName: keep existing error-if-not-found behavior
            $splatParams.DocumentName = $Metadata.DocumentName
        }
        elseif ($extractedDocName) {
            # Complete document detected: target by its metadata.name, append if absent
            $splatParams.DocumentName     = $extractedDocName
            $splatParams.AppendIfNotFound = $true
        }

        Update-MultiDocumentSecret @splatParams
        return
    }

    try {
        foreach ($item in $setPaths) {
            if ($null -eq $item.Value) {
                Invoke-SopsUnset -Path $item.Path -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
                continue
            }

            $valueStr = ConvertTo-SopsValueString -Value $item.Value
            $setExpression = "$($item.Path) $valueStr"
            Invoke-SopsSet -SetExpression $setExpression -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
        }
    }
    catch {
        throw "Failed to update existing secret '$SecretName': $_"
    }
}

function ConvertTo-SopsValueString {
    <#
    .SYNOPSIS
    Converts a value to a SOPS-compatible string representation.

    .DESCRIPTION
    Formats values for use in SOPS --set expressions. Handles empty strings,
    booleans, numbers, and regular strings with proper quoting and escaping.

    .PARAMETER Value
    The value to convert.

    .OUTPUTS
    String representation suitable for SOPS --set.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        $Value
    )

    if ($Value -eq '') {
        return '""'
    }

    if ($Value -is [bool]) {
        return $Value.ToString().ToLower()
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return $Value.ToString()
    }

    # String value - wrap in quotes and escape internal quotes
    $escaped = $Value -replace '"', '\"'
    return "`"$escaped`""
}
