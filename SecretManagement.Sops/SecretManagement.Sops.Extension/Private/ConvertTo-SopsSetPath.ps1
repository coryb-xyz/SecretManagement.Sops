function ConvertTo-SopsSetPath {
    <#
    .SYNOPSIS
    Convert hashtable structure to SOPS --set JSONPath expressions (Extension wrapper).

    .DESCRIPTION
    Extension wrapper that calls the main module's ConvertTo-SopsSetPath with
    strict scalar validation enabled (ScalarBehavior = 'Throw').

    Recursively walks a hashtable/OrderedDictionary structure and generates
    SOPS --set compatible JSONPath expressions for each leaf value.

    .PARAMETER Object
    The hashtable or OrderedDictionary to convert.

    .PARAMETER Prefix
    Internal parameter used during recursion to track the current path.

    .OUTPUTS
    Array of hashtables with Path and Value properties.

    .EXAMPLE
    $patch = @{ stringData = @{ 'db-password' = 'newPass'; 'api-key' = 'secret123' } }
    $setPaths = ConvertTo-SopsSetPath -Object $patch
    # Returns:
    # @(
    #   @{ Path = '["stringData"]["db-password"]'; Value = 'newPass' },
    #   @{ Path = '["stringData"]["api-key"]'; Value = 'secret123' }
    # )

    .EXAMPLE
    foreach ($item in (ConvertTo-SopsSetPath -Object $patch)) {
        sops --set "$($item.Path) `"$($item.Value)`"" $filePath
    }

    .NOTES
    This consolidation shares implementation with the main module's ConvertTo-SopsSetPath.
    The Extension version uses strict validation (throws on top-level scalars).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter()]
        [string]$Prefix = ''
    )

    # Get the main module's implementation path
    $parentModulePath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $mainFunctionPath = Join-Path $parentModulePath 'Private\ConvertTo-SopsSetPath.ps1'

    # Dot-source the main implementation
    . $mainFunctionPath

    # Call with Extension-specific behavior (strict scalar validation)
    return ConvertTo-SopsSetPath -Object $Object -Prefix $Prefix -ScalarBehavior 'Throw'
}
