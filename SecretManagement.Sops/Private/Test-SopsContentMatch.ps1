function Test-SopsContentMatch {
    <#
    .SYNOPSIS
    Tests if a plaintext YAML file contains keys that would be encrypted by SOPS.

    .DESCRIPTION
    Parses YAML file and checks if any top-level keys match the encryption filter
    defined in the creation rule (encrypted_regex, encrypted_suffix, etc.).

    This implements SOPS content filtering logic:
    - encrypted_regex: Encrypt keys matching regex
    - unencrypted_regex: Encrypt all EXCEPT keys matching regex
    - encrypted_suffix: Encrypt keys ending with suffix
    - unencrypted_suffix: Encrypt all EXCEPT keys ending with suffix
    - No filter: Encrypt all values

    Filter types are mutually exclusive and evaluated in priority order.

    .PARAMETER FilePath
    Path to the plaintext YAML file.

    .PARAMETER CreationRule
    The matched creation rule hashtable.

    .OUTPUTS
    Boolean - $true if file contains encryptable content, $false otherwise.

    .EXAMPLE
    $hasContent = Test-SopsContentMatch -FilePath 'C:\secrets\k8s-secret.yaml' -CreationRule $rule
    if ($hasContent) {
        Write-Host "File contains keys that would be encrypted"
    }

    .NOTES
    Only checks top-level keys (sufficient for Kubernetes secrets with data/stringData).
    Gracefully handles invalid YAML by returning $false with a warning.
    Requires powershell-yaml module.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [hashtable]$CreationRule
    )

    try {
        # Import YAML module (already available)
        Import-Module powershell-yaml -ErrorAction Stop

        # Read and parse YAML
        $yamlContent = Get-Content -Path $FilePath -Raw -ErrorAction Stop

        # Handle empty files
        if ([string]::IsNullOrWhiteSpace($yamlContent)) {
            return $false
        }

        $parsed = ConvertFrom-Yaml -Yaml $yamlContent -ErrorAction Stop

        # If not a hashtable/dictionary, no keys to encrypt
        if ($parsed -isnot [hashtable] -and $parsed -isnot [System.Collections.IDictionary]) {
            return $false
        }

        # Get top-level keys
        $keys = @($parsed.Keys)

        if ($keys.Count -eq 0) {
            return $false
        }

        # Apply content filtering logic
        # Priority: encrypted_regex > unencrypted_regex > encrypted_suffix > unencrypted_suffix > all

        if ($CreationRule.EncryptedRegex) {
            # Only encrypt keys matching regex
            foreach ($key in $keys) {
                if ($key -match $CreationRule.EncryptedRegex) {
                    return $true
                }
            }
            return $false
        }

        if ($CreationRule.UnencryptedRegex) {
            # Encrypt all EXCEPT keys matching regex
            foreach ($key in $keys) {
                if ($key -notmatch $CreationRule.UnencryptedRegex) {
                    return $true
                }
            }
            return $false
        }

        if ($CreationRule.EncryptedSuffix) {
            # Only encrypt keys ending with suffix
            foreach ($key in $keys) {
                if ($key.EndsWith($CreationRule.EncryptedSuffix)) {
                    return $true
                }
            }
            return $false
        }

        if ($CreationRule.UnencryptedSuffix) {
            # Encrypt all EXCEPT keys ending with suffix
            foreach ($key in $keys) {
                if (-not $key.EndsWith($CreationRule.UnencryptedSuffix)) {
                    return $true
                }
            }
            return $false
        }

        # No filter specified - all values would be encrypted
        return $true
    }
    catch {
        Write-Warning "Failed to parse YAML content for '$FilePath': $_"
        return $false
    }
}
