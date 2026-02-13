function ConvertTo-SecretYaml {
    <#
    .SYNOPSIS
    Convert various secret types to YAML-compatible structure.

    .DESCRIPTION
    Converts SecretManagement framework secret types (String, SecureString,
    PSCredential, Hashtable, Byte[]) to structures suitable for YAML serialization.

    String values with path syntax (e.g., ".field: value") are preserved as-is
    for ConvertTo-SopsSetPathFromString. Other strings are parsed as YAML when
    possible, falling back to the raw string.

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
    # Returns: $k8sSecret as-is
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($Secret -is [string]) {
        # Path syntax must be checked before YAML parsing since it is valid YAML
        if (Test-PathBasedSyntax -InputString $Secret) {
            return $Secret
        }

        try {
            Import-Module powershell-yaml -ErrorAction Stop
            $parsed = $Secret | ConvertFrom-Yaml -ErrorAction Stop

            if ($parsed -is [hashtable] -or $parsed -is [System.Collections.Specialized.OrderedDictionary]) {
                return $parsed
            }

            if ($parsed -is [PSCustomObject]) {
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

    if ($Secret -is [System.Security.SecureString]) {
        return $Secret | ConvertFrom-SecureString -AsPlainText
    }

    if ($Secret -is [PSCredential]) {
        return @{
            username = $Secret.UserName
            password = $Secret.Password | ConvertFrom-SecureString -AsPlainText
        }
    }

    if ($Secret -is [System.Collections.IDictionary]) {
        return $Secret
    }

    if ($Secret -is [byte[]]) {
        return [Convert]::ToBase64String($Secret)
    }

    throw "Unsupported secret type: $($Secret.GetType().FullName). Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
}
