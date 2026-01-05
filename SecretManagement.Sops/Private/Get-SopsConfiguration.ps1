function Get-SopsConfiguration {
    <#
    .SYNOPSIS
    Parses .sops.yaml configuration file and extracts filtering settings.

    .DESCRIPTION
    Reads the .sops.yaml file from the vault root directory and extracts
    unencrypted_suffix values from all creation_rules.

    These suffixes are used to exclude plaintext working copies when
    RequireEncryption filtering is enabled.

    .PARAMETER VaultPath
    Path to the vault root directory.

    .OUTPUTS
    Hashtable with keys:
    - UnencryptedSuffixes: Array of unique suffix strings
    - CreationRules: Array of parsed creation rule hashtables
    - Found: Boolean indicating if .sops.yaml was found and parsed

    .EXAMPLE
    $config = Get-SopsConfiguration -VaultPath 'C:\secrets'
    if ($config.Found) {
        Write-Host "Excluding files with suffixes: $($config.UnencryptedSuffixes -join ', ')"
    }

    .NOTES
    Requires powershell-yaml module for YAML parsing.
    Returns empty result on errors (graceful degradation).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$VaultPath
    )

    # Initialize result
    $result = @{
        UnencryptedSuffixes = @()
        CreationRules       = @()
        Found               = $false
    }

    # Check if .sops.yaml exists
    $sopsConfigPath = Join-Path $VaultPath '.sops.yaml'
    if (-not (Test-Path $sopsConfigPath)) {
        return $result
    }

    try {
        # Import powershell-yaml module (already available in project)
        Import-Module powershell-yaml -ErrorAction Stop

        # Parse .sops.yaml
        $configContent = Get-Content -Path $sopsConfigPath -Raw
        $config = ConvertFrom-Yaml -Yaml $configContent

        # Extract unencrypted_suffix from all creation_rules
        if ($config.creation_rules) {
            $suffixes = @()

            foreach ($rule in $config.creation_rules) {
                if ($rule.unencrypted_suffix) {
                    $suffixes += $rule.unencrypted_suffix
                }
            }

            # Return unique suffixes only
            if ($suffixes.Count -gt 0) {
                $result.UnencryptedSuffixes = $suffixes | Select-Object -Unique
            }

            # Extract full creation_rules for RequireSopsMatch filtering
            $parsedRules = @()
            foreach ($rule in $config.creation_rules) {
                $parsedRule = @{
                    PathRegex         = $rule.path_regex
                    EncryptedRegex    = $rule.encrypted_regex
                    EncryptedSuffix   = $rule.encrypted_suffix
                    UnencryptedRegex  = $rule.unencrypted_regex
                    UnencryptedSuffix = $rule.unencrypted_suffix
                }
                $parsedRules += $parsedRule
            }
            $result.CreationRules = $parsedRules

            $result.Found = $true
        }
    }
    catch {
        # Graceful degradation - log warning but don't fail
        Write-Warning "Failed to parse .sops.yaml at '$sopsConfigPath': $_"
        # Return empty result (already initialized)
    }

    return $result
}
