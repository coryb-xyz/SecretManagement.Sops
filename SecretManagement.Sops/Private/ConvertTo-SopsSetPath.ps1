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

    function Test-DictionaryType {
        param([object]$Value)
        return $Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]
    }

    function New-PathResult {
        param(
            [string]$Path,
            [object]$Value
        )
        return @{
            Path  = $Path
            Value = $Value
        }
    }

    function Get-JsonPath {
        param(
            [string]$Prefix,
            [string]$Key
        )
        if ($Prefix) {
            return "$Prefix[`"$Key`"]"
        }
        return "[`"$Key`"]"
    }

    function Get-ArrayPath {
        param(
            [string]$Prefix,
            [int]$Index
        )
        if ($Prefix) {
            return "$Prefix[$Index]"
        }
        return "[$Index]"
    }

    $results = @()

    if (Test-DictionaryType -Value $Object) {
        foreach ($key in $Object.Keys) {
            $value = $Object[$key]
            $currentPath = Get-JsonPath -Prefix $Prefix -Key $key

            if (Test-DictionaryType -Value $value) {
                $results += ConvertTo-SopsSetPath -Object $value -Prefix $currentPath -ScalarBehavior $ScalarBehavior
            } else {
                $results += New-PathResult -Path $currentPath -Value $value
            }
        }
    } elseif ($Object -is [array]) {
        for ($i = 0; $i -lt $Object.Count; $i++) {
            $value = $Object[$i]
            $currentPath = Get-ArrayPath -Prefix $Prefix -Index $i

            if (Test-DictionaryType -Value $value) {
                $results += ConvertTo-SopsSetPath -Object $value -Prefix $currentPath -ScalarBehavior $ScalarBehavior
            } else {
                $results += New-PathResult -Path $currentPath -Value $value
            }
        }
    } else {
        # Scalar value
        if ($Prefix) {
            $results += New-PathResult -Path $Prefix -Value $Object
        } elseif ($ScalarBehavior -eq 'Throw') {
            throw "Cannot convert scalar value to SOPS path. Value must be a hashtable or OrderedDictionary."
        } else {
            Write-Verbose "Scalar value provided without structure - wrapping in default 'value' key"
            $results += New-PathResult -Path '["value"]' -Value $Object
        }
    }

    return $results
}
