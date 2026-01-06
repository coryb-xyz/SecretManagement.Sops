function Test-FileContainsKeys {
    <#
    .SYNOPSIS
    Tests if a YAML file contains keys matching an encrypted_regex pattern.

    .DESCRIPTION
    Parses a YAML file and checks if any top-level keys match the provided
    encrypted_regex pattern from a SOPS creation_rule.

    This is used to determine if a file should be encrypted based on its content.
    For example, Kubernetes Secrets have 'data' or 'stringData' keys that should
    be encrypted, while ConfigMaps do not.

    .PARAMETER FilePath
    The path to the YAML file to check.

    .PARAMETER EncryptedRegex
    The regex pattern from the SOPS creation_rule encrypted_regex field.

    .OUTPUTS
    Boolean indicating whether the file contains matching keys.

    .EXAMPLE
    Test-FileContainsKeys -FilePath 'k8s-secret.yaml' `
        -EncryptedRegex '^(data|stringData)$'
    # Returns: $true (if file has data or stringData keys)

    .EXAMPLE
    Test-FileContainsKeys -FilePath 'k8s-configmap.yaml' `
        -EncryptedRegex '^(data|stringData)$'
    # Returns: $false (ConfigMaps don't have these keys)

    .NOTES
    Requires powershell-yaml module for YAML parsing.
    Returns false on parsing errors (graceful degradation).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$EncryptedRegex
    )

    try {
        # Import powershell-yaml module
        Import-Module powershell-yaml -ErrorAction Stop

        # Read and parse YAML file
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        $yaml = ConvertFrom-Yaml -Yaml $content

        # Check if any top-level keys match the regex
        foreach ($key in $yaml.Keys) {
            if ($key -match $EncryptedRegex) {
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Warning "Failed to parse YAML file '$FilePath': $_"
        return $false
    }
}
