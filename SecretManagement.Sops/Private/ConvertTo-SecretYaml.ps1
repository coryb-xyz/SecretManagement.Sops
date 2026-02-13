function ConvertTo-SecretYaml {
    <#
    .SYNOPSIS
    Convert various secret types to YAML-compatible structure.

    .DESCRIPTION
    Converts SecretManagement framework secret types (String, SecureString,
    PSCredential, Hashtable, Byte[]) to structures suitable for YAML serialization.

    - String values are returned as-is (plain text)
    - SecureString converted to plain text
    - PSCredential converted to username/password hashtable
    - Hashtable passed through (supports K8s secrets with apiVersion/kind/metadata)
    - Byte[] converted to base64 with encoding metadata

    .PARAMETER Secret
    The secret object to convert.

    .PARAMETER Name
    The name of the secret (used for context in error messages).

    .PARAMETER EnablePathSyntaxDetection
    Enable detection of path-based syntax (e.g., ".stringData.password: value").
    Used by the Extension module for Set-Secret operations.

    .PARAMETER EnableYamlParsing
    Enable YAML string parsing to convert structured YAML strings to hashtables.
    When enabled, Byte[] returns a plain base64 string instead of structured format,
    and unsupported types throw instead of emitting a warning.

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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$EnablePathSyntaxDetection,

        [switch]$EnableYamlParsing
    )

    if ($Secret -is [string]) {
        # Path syntax (e.g., ".stringData.password: value") must be preserved as-is
        # for ConvertTo-SopsSetPathFromString; check before YAML parsing since it is valid YAML
        if ($EnablePathSyntaxDetection) {
            $hasCommand = Get-Command Test-PathBasedSyntax -ErrorAction SilentlyContinue
            if ($hasCommand -and (Test-PathBasedSyntax -InputString $Secret)) {
                return $Secret
            }
        }

        if ($EnableYamlParsing) {
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

    if ($Secret -is [hashtable] -or $Secret -is [System.Collections.Specialized.OrderedDictionary]) {
        return $Secret
    }

    if ($Secret -is [byte[]]) {
        $base64 = [Convert]::ToBase64String($Secret)
        if ($EnableYamlParsing) {
            return $base64
        }
        return @{ data = $base64; encoding = 'base64' }
    }

    if ($Secret -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $Secret.Keys) {
            $ht[$key] = $Secret[$key]
        }
        return $ht
    }

    $typeName = $Secret.GetType().FullName
    if ($EnableYamlParsing) {
        throw "Unsupported secret type: $typeName. Supported types: String, SecureString, PSCredential, Byte[], Hashtable"
    }

    Write-Warning "Secret '$Name' has unexpected type: $typeName. Attempting to use as-is."
    return $Secret
}
