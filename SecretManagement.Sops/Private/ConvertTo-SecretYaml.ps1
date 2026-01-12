function ConvertTo-SecretYaml {
    <#
    .SYNOPSIS
    Convert various secret types to YAML-compatible structure.

    .DESCRIPTION
    Converts SecretManagement framework secret types (String, SecureString,
    PSCredential, Hashtable, Byte[]) to structures suitable for YAML serialization.

    Per user requirements:
    - String values are returned as-is (plain text)
    - SecureString converted to plain text
    - PSCredential converted to username/password hashtable
    - Hashtable used as-is (especially for K8s secrets with apiVersion/kind/metadata)
    - Byte[] converted to base64

    .PARAMETER Secret
    The secret object to convert.

    .PARAMETER Name
    The name of the secret (used for context in error messages).

    .PARAMETER EnablePathSyntaxDetection
    Enable detection of path-based syntax (e.g., ".stringData.password: value").
    Used by the Extension module for Set-Secret operations.

    .PARAMETER EnableYamlParsing
    Enable YAML string parsing to convert structured YAML strings to hashtables.
    Used by the Extension module for Set-Secret operations.

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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [switch]$EnablePathSyntaxDetection,

        [Parameter()]
        [switch]$EnableYamlParsing
    )

    # Handle different secret types
    if ($Secret -is [string]) {
        # Extension-specific logic for strings: check for path syntax and YAML parsing
        if ($EnablePathSyntaxDetection -or $EnableYamlParsing) {
            # Check for path-based syntax FIRST before trying YAML parsing
            # Path syntax like ".stringData.password: value" is technically valid YAML,
            # but we need to preserve it as a string for ConvertTo-SopsSetPathFromString
            if ($EnablePathSyntaxDetection) {
                # Requires Test-PathBasedSyntax function (Extension module only)
                if (Get-Command Test-PathBasedSyntax -ErrorAction SilentlyContinue) {
                    if (Test-PathBasedSyntax -InputString $Secret) {
                        return $Secret
                    }
                }
            }

            # Try to parse as YAML if enabled
            if ($EnableYamlParsing) {
                try {
                    Import-Module powershell-yaml -ErrorAction Stop
                    $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop

                    # Check if we got a structured object
                    if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
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
            }
        }

        # Return string as-is (plain text, per user preference)
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
    elseif ($Secret -is [PSCredential]) {
        # Convert PSCredential to username/password hashtable
        return @{
            username = $Secret.UserName
            password = ($Secret.Password | ConvertFrom-SecureString -AsPlainText)
        }
    }
    elseif ($Secret -is [hashtable] -or $Secret -is [System.Collections.Specialized.OrderedDictionary]) {
        # Use hashtable as-is (per user preference)
        # This allows K8s secrets with apiVersion/kind/metadata to pass through directly
        return $Secret
    }
    elseif ($Secret -is [byte[]]) {
        # Convert byte array to base64
        $base64 = [Convert]::ToBase64String($Secret)

        # Extension module uses simple base64 string, main module uses structured format
        if ($EnableYamlParsing) {
            return $base64
        }
        else {
            return @{
                data = $base64
                encoding = 'base64'
            }
        }
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
        # Handle unexpected types
        if ($EnableYamlParsing) {
            # Extension module: throw for unsupported types
            throw "Unsupported secret type: $($Secret.GetType().FullName). Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
        }
        else {
            # Main module: warn and attempt to use as-is
            Write-Warning "Secret '$Name' has unexpected type: $($Secret.GetType().FullName). Attempting to use as-is."
            return $Secret
        }
    }
}
