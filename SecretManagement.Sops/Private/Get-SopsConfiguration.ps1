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
    - CreationRules: Array of hashtables containing PathRegex, EncryptedRegex, UnencryptedSuffix
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

    $result = @{
        UnencryptedSuffixes = @()
        Found               = $false
        CreationRules       = @()
    }

    $sopsConfigPath = Join-Path $VaultPath '.sops.yaml'
    if (-not (Test-Path $sopsConfigPath)) {
        return $result
    }

    try {
        Import-Module powershell-yaml -ErrorAction Stop

        $configContent = Get-Content -Path $sopsConfigPath -Raw
        $config = ConvertFrom-Yaml -Yaml $configContent

        if ($config.creation_rules) {
            $result.CreationRules = $config.creation_rules | ForEach-Object {
                @{
                    PathRegex         = $_.path_regex
                    EncryptedRegex    = $_.encrypted_regex
                    UnencryptedSuffix = $_.unencrypted_suffix
                }
            }

            $result.UnencryptedSuffixes = $config.creation_rules |
                Where-Object { $_.unencrypted_suffix } |
                ForEach-Object { $_.unencrypted_suffix } |
                Select-Object -Unique

            $result.Found = $true
        }
    }
    catch {
        Write-Warning "Failed to parse .sops.yaml at '$sopsConfigPath': $_"
    }

    return $result
}
