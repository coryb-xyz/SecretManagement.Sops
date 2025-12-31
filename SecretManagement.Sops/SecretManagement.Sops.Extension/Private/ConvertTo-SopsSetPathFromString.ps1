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
        $value = if ($extractedValue -eq 'null' -or $extractedValue -eq '$null') {
            $null
        }
 else {
            $extractedValue
        }

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

            # Attempt 1: Parse YAML as-is
            try {
                $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop

                if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                    # Successfully parsed as YAML structure - convert to set paths
                    return ConvertTo-SopsSetPath -Object $parsed
                }
                elseif ($null -ne $parsed -and $parsed -isnot [string]) {
                    # Parsed to some other structured type - convert to hashtable first
                    $ht = @{}
                    if ($parsed -is [PSCustomObject]) {
                        $parsed.PSObject.Properties | ForEach-Object {
                            $ht[$_.Name] = $_.Value
                        }
                        return ConvertTo-SopsSetPath -Object $ht
                    }
                }
            }
            catch {
                # Attempt 2: If YAML parsing failed and string contains tabs, normalize and retry
                if ($Secret -match "`t") {
                    Write-Verbose "Normalizing tab characters to spaces in YAML input"
                    $normalized = $Secret -replace "`t", "  "  # Replace each tab with 2 spaces

                    try {
                        $parsed = $normalized | ConvertFrom-Yaml -ErrorAction Stop

                        if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                            # Successfully parsed after normalization - convert to set paths
                            return ConvertTo-SopsSetPath -Object $parsed
                        }
                        elseif ($null -ne $parsed -and $parsed -isnot [string]) {
                            # Parsed to some other structured type - convert to hashtable first
                            $ht = @{}
                            if ($parsed -is [PSCustomObject]) {
                                $parsed.PSObject.Properties | ForEach-Object {
                                    $ht[$_.Name] = $_.Value
                                }
                                return ConvertTo-SopsSetPath -Object $ht
                            }
                        }
                    }
                    catch {
                        # YAML parsing failed even after tab normalization
                        throw "Failed to parse YAML input after normalization: $($_.Exception.Message). Check YAML syntax."
                    }
                }
                else {
                    # YAML parsing failed and no tabs detected - likely a syntax error
                    throw "Failed to parse YAML input: $($_.Exception.Message). Content appears to be YAML but has syntax errors."
                }
            }
        }
        catch {
            # powershell-yaml module not available or other critical error
            if ($_.Exception.Message -match "Failed to parse YAML") {
                # Re-throw our custom error messages
                throw
            }
            # Fall through to plain string handling if module not available
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
