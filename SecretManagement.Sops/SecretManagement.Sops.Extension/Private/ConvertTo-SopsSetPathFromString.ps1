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

    # Try to detect path-based syntax: .path.to.field: value
    # Matches patterns like:
    # - .stringData.password: newValue
    # - .metadata.name: mySecret
    # - .data["api-key"]: secret123
    # Use shared helper to ensure consistent detection logic
    if (Test-PathBasedSyntax -InputString $Secret) {
        # Extract the path and value
        $parts = $Secret -split ':\s*', 2
        $pathExpression = $parts[0].Trim()
        $extractedValue = if ($parts.Count -eq 2) { $parts[1].Trim() } else { '' }

        # Convert string literals "null" and "$null" to PowerShell $null
        # This enables key removal: ".stringData.host: null" removes the key
        $isNullLiteral = $extractedValue -eq 'null' -or $extractedValue -eq '$null'
        $value = if ($isNullLiteral) { $null } else { $extractedValue }

        # Convert yq-style path to SOPS JSONPath
        # .stringData.password -> ["stringData"]["password"]
        # .data["api-key"] -> ["data"]["api-key"]

        # Remove leading dot
        $pathExpression = $pathExpression.TrimStart('.')

        # Split by dots, but preserve bracketed sections
        $sopsPath = ''
        $segments = @()
        $current = ''
        $inBracket = $false

        for ($i = 0; $i -lt $pathExpression.Length; $i++) {
            $char = $pathExpression[$i]

            if ($char -eq '[') {
                if ($current) {
                    $segments += $current
                    $current = ''
                }
                $inBracket = $true
                $current += $char
            }
            elseif ($char -eq ']') {
                $current += $char
                $segments += $current
                $current = ''
                $inBracket = $false
            }
            elseif ($char -eq '.' -and -not $inBracket) {
                if ($current) {
                    $segments += $current
                    $current = ''
                }
            }
            else {
                $current += $char
            }
        }

        if ($current) {
            $segments += $current
        }

        # Build SOPS JSONPath from segments
        foreach ($segment in $segments) {
            if ($segment -match '^\[(.+)\]$') {
                # Already bracketed, use as-is
                $sopsPath += $segment
            }
            else {
                # Plain key, wrap in brackets and quotes
                $sopsPath += "[`"$segment`"]"
            }
        }

        return @(
            @{
                Path  = $sopsPath
                Value = $value
            }
        )
    }

    # Try to parse as YAML if the string looks like YAML
    # Use heuristic detection to avoid false positives on passwords/URLs
    if (Test-YamlLikeString -InputString $Secret) {
        try {
            Import-Module powershell-yaml -ErrorAction Stop

            # Helper to convert parsed YAML to set paths
            $convertParsedYaml = {
                param($parsed)
                if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                    return ConvertTo-SopsSetPath -Object $parsed
                }
                if ($parsed -is [PSCustomObject]) {
                    $ht = @{}
                    $parsed.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                    return ConvertTo-SopsSetPath -Object $ht
                }
                return $null
            }

            # Attempt 1: Parse YAML as-is
            $parsed = $null
            $parseError = $null
            try {
                $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop
            }
            catch {
                $parseError = $_
            }

            # If parsing succeeded, try to convert
            if ($null -eq $parseError -and $null -ne $parsed -and $parsed -isnot [string]) {
                $result = & $convertParsedYaml $parsed
                if ($null -ne $result) { return $result }
            }

            # Attempt 2: If parsing failed and string contains tabs, normalize and retry
            if ($null -ne $parseError -and $Secret -match "`t") {
                Write-Verbose "Normalizing tab characters to spaces in YAML input"
                $normalized = $Secret -replace "`t", "  "

                try {
                    $parsed = $normalized | ConvertFrom-Yaml -ErrorAction Stop
                    if ($null -ne $parsed -and $parsed -isnot [string]) {
                        $result = & $convertParsedYaml $parsed
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
        }
        catch {
            # Re-throw YAML parsing errors, fall through for module not available
            if ($_.Exception.Message -match "Failed to parse YAML") { throw }
        }
    }

    # Plain string - store in "value" key
    return @(
        @{
            Path  = '["value"]'
            Value = $Secret
        }
    )
}
