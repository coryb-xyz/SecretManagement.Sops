function ConvertTo-SopsSetPathFromString {
    <#
    .SYNOPSIS
    Convert string input to SOPS --set path expressions.

    .DESCRIPTION
    Handles three types of string input for Set-Secret:
    1. Path-based syntax (yq-style): ".stringData.password: newValue"
    2. YAML content: Multi-line YAML that gets parsed into paths
    3. Plain string: Simple value stored in "value" key

    This enables both targeted updates and YAML-based patching.

    .PARAMETER Secret
    The string secret to convert.

    .OUTPUTS
    Array of hashtables with Path and Value properties for sops --set.

    .EXAMPLE
    # Path-based syntax
    ConvertTo-SopsSetPathFromString -Secret ".stringData.password: newPass"
    # Returns: @{ Path = '["stringData"]["password"]'; Value = 'newPass' }

    .EXAMPLE
    # YAML content
    $yaml = @"
    stringData:
      password: newPass
      username: admin
    "@
    ConvertTo-SopsSetPathFromString -Secret $yaml
    # Returns:
    # @(
    #   @{ Path = '["stringData"]["password"]'; Value = 'newPass' },
    #   @{ Path = '["stringData"]["username"]'; Value = 'admin' }
    # )

    .EXAMPLE
    # Plain string
    ConvertTo-SopsSetPathFromString -Secret "just-a-password"
    # Returns: @{ Path = '["value"]'; Value = 'just-a-password' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Secret
    )

    if (Test-PathBasedSyntax -InputString $Secret) {
        return ConvertFrom-PathSyntax -InputString $Secret
    }

    if (Test-YamlLikeString -InputString $Secret) {
        $result = ConvertFrom-YamlString -InputString $Secret
        if ($null -ne $result) { return $result }
    }

    # Plain string - store in "value" key
    return @(
        @{
            Path  = '["value"]'
            Value = $Secret
        }
    )
}

function ConvertFrom-PathSyntax {
    <#
    .SYNOPSIS
    Parses yq-style path syntax into a SOPS --set path expression.

    .DESCRIPTION
    Converts ".stringData.password: newValue" into a hashtable with
    Path = '["stringData"]["password"]' and Value = 'newValue'.

    Null literals ("null", "$null") are converted to $null to enable key removal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    $parts = $InputString -split ':\s*', 2
    $pathExpression = $parts[0].Trim().TrimStart('.')
    $extractedValue = if ($parts.Count -eq 2) { $parts[1].Trim() } else { '' }

    # "null" / "$null" become $null to enable key removal via sops --unset
    $isNullLiteral = $extractedValue -eq 'null' -or $extractedValue -eq '$null'
    $value = if ($isNullLiteral) { $null } else { $extractedValue }

    # Split path into segments, preserving bracketed sections like ["api-key"]
    $segments = [regex]::Matches($pathExpression, '\[[^\]]+\]|[^.\[]+')

    $sopsPath = ''
    foreach ($segment in $segments) {
        if ($segment.Value -match '^\[') {
            $sopsPath += $segment.Value
        }
        else {
            $sopsPath += "[`"$($segment.Value)`"]"
        }
    }

    return @(
        @{
            Path  = $sopsPath
            Value = $value
        }
    )
}

function ConvertFrom-YamlString {
    <#
    .SYNOPSIS
    Parses a YAML string into SOPS --set path expressions.

    .DESCRIPTION
    Attempts to parse the input as YAML content. If parsing fails due to tab
    characters, normalizes tabs to spaces and retries. Returns $null if the
    powershell-yaml module is unavailable (allowing fallback to plain string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    try {
        Import-Module powershell-yaml -ErrorAction Stop
    }
    catch {
        return $null
    }

    $parsed = $null
    $parseError = $null
    try {
        $parsed = $InputString | ConvertFrom-Yaml -ErrorAction Stop
    }
    catch {
        $parseError = $_
    }

    if ($null -eq $parseError -and $null -ne $parsed -and $parsed -isnot [string]) {
        $result = ConvertFrom-ParsedYaml -Parsed $parsed
        if ($null -ne $result) { return $result }
    }

    # If parsing failed and input contains tabs, normalize tabs to spaces and retry
    if ($null -ne $parseError -and $InputString -match "`t") {
        Write-Verbose "Normalizing tab characters to spaces in YAML input"
        $normalized = $InputString -replace "`t", "  "

        try {
            $parsed = $normalized | ConvertFrom-Yaml -ErrorAction Stop
            if ($null -ne $parsed -and $parsed -isnot [string]) {
                $result = ConvertFrom-ParsedYaml -Parsed $parsed
                if ($null -ne $result) { return $result }
            }
        }
        catch {
            throw "Failed to parse YAML input after normalization: $($_.Exception.Message). Check YAML syntax."
        }
    }
    elseif ($null -ne $parseError) {
        throw "Failed to parse YAML input: $($parseError.Exception.Message). Content appears to be YAML but has syntax errors."
    }

    return $null
}

function ConvertFrom-ParsedYaml {
    <#
    .SYNOPSIS
    Converts a parsed YAML object (hashtable, OrderedDictionary, or PSCustomObject)
    to SOPS --set path expressions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Parsed
    )

    if ($Parsed -is [hashtable] -or $Parsed -is [System.Collections.Specialized.OrderedDictionary]) {
        return ConvertTo-SopsSetPath -Object $Parsed
    }

    if ($Parsed -is [PSCustomObject]) {
        $ht = @{}
        $Parsed.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        return ConvertTo-SopsSetPath -Object $ht
    }

    return $null
}
