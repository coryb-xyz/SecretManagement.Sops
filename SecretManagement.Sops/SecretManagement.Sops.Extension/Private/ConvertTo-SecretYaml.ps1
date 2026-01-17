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

    # String: check for path syntax first, then try YAML parsing
    if ($Secret -is [string]) {
        # Path syntax (e.g., ".stringData.password: value") must be preserved as string
        # for ConvertTo-SopsSetPathFromString - check before YAML parsing since it's valid YAML
        if (Test-PathBasedSyntax -InputString $Secret) {
            return $Secret
        }

        # Try to parse as structured YAML (e.g., from New-KubernetesSecret)
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

    # Hashtable/OrderedDictionary: pass through (supports K8s secrets with apiVersion/kind/metadata)
    if ($Secret -is [hashtable] -or $Secret -is [System.Collections.Specialized.OrderedDictionary]) {
        return $Secret
    }

    # Byte array: convert to base64 string
    if ($Secret -is [byte[]]) {
        return [Convert]::ToBase64String($Secret)
    }

    # Other dictionary types: convert to hashtable
    if ($Secret -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $Secret.Keys) {
            $ht[$key] = $Secret[$key]
        }
        return $ht
    }

    throw "Unsupported secret type: $($Secret.GetType().FullName). Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
}
