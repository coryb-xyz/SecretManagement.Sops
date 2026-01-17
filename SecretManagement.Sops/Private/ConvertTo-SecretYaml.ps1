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

    # String handling with optional path syntax detection and YAML parsing
    if ($Secret -is [string]) {
        # Check for path-based syntax first (e.g., ".stringData.password: value")
        # Path syntax is valid YAML but must be preserved as string for ConvertTo-SopsSetPathFromString
        if ($EnablePathSyntaxDetection) {
            $hasPathSyntaxCommand = Get-Command Test-PathBasedSyntax -ErrorAction SilentlyContinue
            if ($hasPathSyntaxCommand -and (Test-PathBasedSyntax -InputString $Secret)) {
                return $Secret
            }
        }

        # Try to parse as YAML if enabled
        if ($EnableYamlParsing) {
            try {
                Import-Module powershell-yaml -ErrorAction Stop
                $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop

                if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                    return $parsed
                }

                if ($null -ne $parsed -and $parsed -is [PSCustomObject]) {
                    $ht = @{}
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $ht[$prop.Name] = $prop.Value
                    }
                    return $ht
                }
            }
            catch {
                Write-Verbose "YAML parsing failed for secret '$Name': $_"
            }
        }

        return $Secret
    }
    # SecureString: convert to plain text
    if ($Secret -is [System.Security.SecureString]) {
        return $Secret | ConvertFrom-SecureString -AsPlainText
    }

    # PSCredential: convert to username/password hashtable
    if ($Secret -is [PSCredential]) {
        return @{
            username = $Secret.UserName
            password = $Secret.Password | ConvertFrom-SecureString -AsPlainText
        }
    }

    # Hashtable/OrderedDictionary: pass through as-is (supports K8s secrets with apiVersion/kind/metadata)
    if ($Secret -is [hashtable] -or $Secret -is [System.Collections.Specialized.OrderedDictionary]) {
        return $Secret
    }

    # Byte array: convert to base64
    if ($Secret -is [byte[]]) {
        $base64 = [Convert]::ToBase64String($Secret)

        # Extension module uses simple base64 string, main module uses structured format
        if ($EnableYamlParsing) {
            return $base64
        }
        return @{ data = $base64; encoding = 'base64' }
    }

    # Other dictionary types: convert to hashtable
    if ($Secret -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $Secret.Keys) {
            $ht[$key] = $Secret[$key]
        }
        return $ht
    }

    # Unsupported types
    $typeName = $Secret.GetType().FullName
    if ($EnableYamlParsing) {
        throw "Unsupported secret type: $typeName. Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
    }

    Write-Warning "Secret '$Name' has unexpected type: $typeName. Attempting to use as-is."
    return $Secret
}
