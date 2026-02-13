function Test-Dictionary {
    <#
    .SYNOPSIS
    Test whether a value is a hashtable or OrderedDictionary.
    #>
    param([object]$Value)
    $Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]
}

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

    .PARAMETER ScalarBehavior
    Controls how top-level scalar values are handled:
    - 'Wrap' (default): Wraps scalar in default 'value' key for graceful handling
    - 'Throw': Throws an error for top-level scalars (strict validation)

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
        [string]$Prefix = '',

        [Parameter()]
        [ValidateSet('Wrap', 'Throw')]
        [string]$ScalarBehavior = 'Wrap'
    )

    # Build a list of (path, value) entries from dictionary keys or array indices
    if (Test-Dictionary $Object) {
        $entries = foreach ($key in $Object.Keys) {
            [PSCustomObject]@{ Path = "${Prefix}[`"${key}`"]"; Value = $Object[$key] }
        }
    }
    elseif ($Object -is [array]) {
        $entries = for ($i = 0; $i -lt $Object.Count; $i++) {
            [PSCustomObject]@{ Path = "${Prefix}[${i}]"; Value = $Object[$i] }
        }
    }

    if ($entries) {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $entries) {
            if (Test-Dictionary $entry.Value) {
                foreach ($child in (ConvertTo-SopsSetPath -Object $entry.Value -Prefix $entry.Path -ScalarBehavior $ScalarBehavior)) {
                    $results.Add($child)
                }
            }
            else {
                $results.Add(@{ Path = $entry.Path; Value = $entry.Value })
            }
        }
        return @($results)
    }

    # Scalar value with a path prefix is a leaf reached via recursion
    if ($Prefix) {
        return @(@{ Path = $Prefix; Value = $Object })
    }

    if ($ScalarBehavior -eq 'Throw') {
        throw "Cannot convert scalar value to SOPS path. Value must be a hashtable or OrderedDictionary."
    }

    Write-Verbose "Scalar value provided without structure - wrapping in default 'value' key"
    return @(@{ Path = '["value"]'; Value = $Object })
}
