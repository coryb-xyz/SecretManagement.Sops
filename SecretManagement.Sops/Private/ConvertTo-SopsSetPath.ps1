function ConvertTo-SopsSetPath {
    <#
    .SYNOPSIS
    Convert hashtable structure to SOPS --set JSONPath expressions.

    .DESCRIPTION
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter()]
        [string]$Prefix = ''
    )

    $results = @()

    # Handle different object types
    if ($Object -is [hashtable] -or $Object -is [System.Collections.Specialized.OrderedDictionary]) {
        foreach ($key in $Object.Keys) {
            $value = $Object[$key]
            $currentPath = if ($Prefix) {
                "$Prefix[`"$key`"]"
            }
 else {
                "[`"$key`"]"
            }

            # If value is a nested hashtable/OrderedDictionary, recurse
            if ($value -is [hashtable] -or $value -is [System.Collections.Specialized.OrderedDictionary]) {
                $results += ConvertTo-SopsSetPath -Object $value -Prefix $currentPath
            }
            # If value is null, handle specially
            elseif ($null -eq $value) {
                $results += @{
                    Path  = $currentPath
                    Value = $null
                }
            }
            # Leaf value - add to results
            else {
                $results += @{
                    Path  = $currentPath
                    Value = $value
                }
            }
        }
    }
    # Handle arrays
    elseif ($Object -is [array]) {
        for ($i = 0; $i -lt $Object.Count; $i++) {
            $value = $Object[$i]
            $currentPath = if ($Prefix) {
                "$Prefix[$i]"
            }
 else {
                "[$i]"
            }

            # If value is a nested structure, recurse
            if ($value -is [hashtable] -or $value -is [System.Collections.Specialized.OrderedDictionary]) {
                $results += ConvertTo-SopsSetPath -Object $value -Prefix $currentPath
            }
            # Leaf value
            else {
                $results += @{
                    Path  = $currentPath
                    Value = $value
                }
            }
        }
    }
    # Scalar value at top level
    else {
        if ($Prefix) {
            $results += @{
                Path  = $Prefix
                Value = $Object
            }
        }
        else {
            # Top-level scalar - wrap in a default structure
            # This allows graceful handling similar to ConvertTo-SopsSetPathFromString
            Write-Verbose "Scalar value provided without structure - wrapping in default 'value' key"
            $results += @{
                Path  = '["value"]'
                Value = $Object
            }
        }
    }

    return $results
}
