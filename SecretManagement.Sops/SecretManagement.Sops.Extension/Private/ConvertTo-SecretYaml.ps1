function ConvertTo-SecretYaml {
    <#
    .SYNOPSIS
    Convert various secret types to YAML-compatible structure.

    .DESCRIPTION
    Converts SecretManagement framework secret types (String, SecureString,
    PSCredential, Hashtable, Byte[]) to structures suitable for YAML serialization.

    Extension version: This function is identical to the main module's version,
    but always enables ExtensionPath syntax detection and YAML parsing features
    by default for Set-Secret operations.

    Per user requirements:
    - String values with path syntax preserved (e.g., ".field: value")
    - YAML strings parsed to hashtables when possible
    - SecureString converted to plain text
    - PSCredential converted to username/password hashtable
    - Hashtable used as-is (especially for K8s secrets with apiVersion/kind/metadata)
    - Byte[] converted to base64 string

    .PARAMETER Secret
    The secret object to convert.

    .PARAMETER Name
    The name of the secret (used for context in error messages).

    .OUTPUTS
    Object - A YAML-compatible structure.

    .EXAMPLE
    ConvertTo-SecretYaml -Secret 'myPassword' -Name 'db-password'
    # Returns: 'myPassword'

    .EXAMPLE
    ConvertTo-SecretYaml -Secret (ConvertTo-SecureString 'pass' -AsPlainText -Force) -Name 'api-key'
    # Returns: 'pass'

    .EXAMPLE
    ConvertTo-SecretYaml -Secret @{ username = 'admin'; password = 'secret' } -Name 'creds'
    # Returns: @{ username = 'admin'; password = 'secret' }

    .EXAMPLE
    $k8sSecret = @{ apiVersion = 'v1'; kind = 'Secret'; stringData = @{ key = 'value' } }
    ConvertTo-SecretYaml -Secret $k8sSecret -Name 'myapp'
    # Returns: $k8sSecret (as-is, per user preference for K8s secrets)

    .NOTES
    This implementation is consolidated with the main module's ConvertTo-SecretYaml.
    The Extension version has path syntax detection and YAML parsing always enabled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$Name
    )

    # Handle different secret types
    if ($Secret -is [string]) {
        # Extension-specific logic: check for path syntax and YAML parsing
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
            Write-Verbose "YAML parsing failed for secret '$Name': $_"
        }

        # Plain string - return as-is
        return $Secret
    }
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
        # Convert byte array to base64 string (Extension uses simple string format)
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
        # Unsupported type - Extension module throws for clarity
        throw "Unsupported secret type: $($Secret.GetType().FullName). Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
    }
}
