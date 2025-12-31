function Resolve-SecretEntry {
    <#
    .SYNOPSIS
    Resolves a secret name to an index entry with collision handling.

    .DESCRIPTION
    Consolidates the common pattern of building an index and resolving a secret name.
    Handles NotFound and Collision results with appropriate errors.

    .PARAMETER Name
    The secret name to resolve.

    .PARAMETER VaultParameters
    Vault parameters containing Path, FilePattern, Recurse, and NamingStrategy.

    .OUTPUTS
    Hashtable with property:
    - Entry: The resolved secret index entry

    .EXAMPLE
    $result = Resolve-SecretEntry -Name 'myapp' -VaultParameters $params
    $filePath = $result.Entry.FilePath
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters
    )

    # Build the secret index
    $index = Get-SecretIndex `
        -Path $VaultParameters.Path `
        -FilePattern $VaultParameters.FilePattern `
        -Recurse $VaultParameters.Recurse `
        -NamingStrategy $VaultParameters.NamingStrategy

    # Resolve the secret name with namespace support
    $resolutionResult = Resolve-SecretNameWithNamespace -Name $Name -Index $index

    # Handle NotFound
    if ($resolutionResult.Type -eq 'NotFound') {
        throw "Secret '$Name' not found in vault"
    }

    # Handle Collision
    if ($resolutionResult.Type -eq 'Collision') {
        $pathList = $resolutionResult.Entries | ForEach-Object {
            "  - $($_.Name) ($($_.FilePath))"
        } | Join-String -Separator "`n"

        throw @"
Multiple secrets with short name '$Name' found:
$pathList

Please specify the full path.
Example: Get-Secret -Name '$($resolutionResult.Entries[0].Name)'
"@
    }

    # Return the resolved entry
    return @{
        Entry = $resolutionResult.Entry
    }
}
