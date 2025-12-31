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
        [string]$Name
    )

    # Handle different secret types
    if ($Secret -is [string]) {
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
        return @{
            data     = $base64
            encoding = 'base64'
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
        # Attempt to use value as-is for other types
        # This may work for simple types that serialize to YAML cleanly
        Write-Warning "Secret '$Name' has unexpected type: $($Secret.GetType().FullName). Attempting to use as-is."
        return $Secret
    }
}
