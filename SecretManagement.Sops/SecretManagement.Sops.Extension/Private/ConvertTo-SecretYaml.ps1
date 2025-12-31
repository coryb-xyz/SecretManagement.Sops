function ConvertTo-SecretYaml {
    <#
    .SYNOPSIS
    Convert secret values to YAML-compatible structure (Extension version with YAML parsing).

    .DESCRIPTION
    Extension version of ConvertTo-SecretYaml that adds:
    - Path-based syntax detection (e.g., ".stringData.password: value")
    - YAML string parsing for structured content

    This is an enhanced version of the Public module's ConvertTo-SecretYaml with additional
    string handling capabilities needed for Set-Secret operations.

    .PARAMETER Secret
    The secret object to convert.

    .PARAMETER Name
    The name of the secret (used for context in error messages).

    .OUTPUTS
    Object - A YAML-compatible structure (String or Hashtable).

    .EXAMPLE
    ConvertTo-SecretYaml -Secret '.stringData.password: value' -Name 'myapp'
    # Returns: '.stringData.password: value' (path syntax preserved)

    .EXAMPLE
    ConvertTo-SecretYaml -Secret "apiVersion: v1`nkind: Secret" -Name 'k8s'
    # Returns: Parsed hashtable structure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$Name
    )

    # Extension-specific logic for strings: check for path syntax and YAML parsing
    if ($Secret -is [string]) {
        # IMPORTANT: Check for path-based syntax FIRST before trying YAML parsing
        # Path syntax like ".stringData.password: value" is technically valid YAML,
        # but we need to preserve it as a string for ConvertTo-SopsSetPathFromString
        # to handle correctly. Otherwise it gets parsed as @{ ".stringData.password" = "value" }
        # which creates a literal key instead of updating the nested path.
        if (Test-PathBasedSyntax -InputString $Secret) {
            # Path-based syntax detected - return as-is (string)
            # This will be handled by ConvertTo-SopsSetPathFromString in Set-Secret
            return $Secret
        }

        # Try to parse as YAML - if it's structured YAML (like from New-KubernetesSecret),
        # parse and return the structure rather than the raw string
        try {
            Import-Module powershell-yaml -ErrorAction Stop
            $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop

            # Check if we got a structured object (hashtable/ordered dictionary)
            if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                # Successfully parsed as YAML structure - return it
                return $parsed
            }
            elseif ($null -ne $parsed -and $parsed -is [PSCustomObject]) {
                # Convert PSCustomObject to hashtable
                $ht = @{}
                $parsed.PSObject.Properties | ForEach-Object {
                    $ht[$_.Name] = $_.Value
                }
                return $ht
            }
        }
        catch {
            # Not valid YAML or YAML module not available - fall through to plain string handling
        }

        # Plain string - return as-is
        return $Secret
    }
    # --- Core type conversion logic (shared with Public module) ---
    elseif ($Secret -is [System.Security.SecureString]) {
        # Convert SecureString to plain text
        try {
            return ($Secret | ConvertFrom-SecureString -AsPlainText)
        }
        catch {
            throw "Failed to convert SecureString for secret '$Name': $_"
        }
    }
    elseif ($Secret -is [hashtable] -or $Secret -is [System.Collections.Specialized.OrderedDictionary]) {
        # Use hashtable as-is
        # This allows K8s secrets with apiVersion/kind/metadata to pass through directly
        return $Secret
    }
    elseif ($Secret -is [PSCredential]) {
        # Convert PSCredential to username/password hashtable
        $plainPassword = $Secret.Password | ConvertFrom-SecureString -AsPlainText
        return @{
            username = $Secret.UserName
            password = $plainPassword
        }
    }
    elseif ($Secret -is [byte[]]) {
        # Convert byte array to base64 string
        $base64 = [Convert]::ToBase64String($Secret)
        return $base64
    }
    elseif ($Secret -is [System.Collections.IDictionary]) {
        # Handle other dictionary types (convert to hashtable)
        $ht = @{}
        foreach ($key in $Secret.Keys) {
            $ht[$key] = $Secret[$key]
        }
        return $ht
    }
    else {
        # Unsupported type
        throw "Unsupported secret type: $($Secret.GetType().FullName). Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
    }
}
