function Get-SopsEncryptionCandidates {
    <#
    .SYNOPSIS
    Discovers files that should be encrypted according to .sops.yaml configuration.

    .DESCRIPTION
    Scans the vault directory for files matching .sops.yaml creation_rules that
    are not yet encrypted with SOPS. This helps identify plaintext files that
    should be migrated to encrypted storage.

    The function replicates SOPS matching logic:
    1. First matching rule wins (process rules in order)
    2. File must match path_regex
    3. If encrypted_regex is defined, file must contain matching keys
    4. Files matching unencrypted_suffix patterns are excluded (plaintext working copies)
    5. Already-encrypted files are excluded

    .PARAMETER Path
    Path to the vault root directory containing .sops.yaml.

    .OUTPUTS
    String[] - Array of absolute file paths that are candidates for encryption.

    .EXAMPLE
    Get-SopsEncryptionCandidates -Path 'C:\secrets'
    # Returns: @('C:\secrets\config.yaml', 'C:\secrets\api-key.yaml')

    .EXAMPLE
    # Migration workflow
    $candidates = Get-SopsEncryptionCandidates -Path 'C:\secrets'
    foreach ($candidateFile in $candidates) {
        Write-Host "Encrypting: $candidateFile"
        sops --encrypt --in-place $candidateFile
    }

    .EXAMPLE
    # CI/CD validation
    $unencrypted = Get-SopsEncryptionCandidates -Path $env:SECRETS_DIR
    if ($unencrypted.Count -gt 0) {
        throw "Security violation: Found unencrypted secret files"
    }

    .NOTES
    Requires .sops.yaml to exist in Path. Returns empty array if not found.
    Uses Test-SopsEncrypted for fast, reliable encryption detection via streaming state machine.
    File patterns are automatically derived from path_regex patterns in .sops.yaml.
    Always searches recursively through all subdirectories.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path
    )

    $config = Get-SopsConfiguration -VaultPath $Path
    if (-not $config.Found) {
        Write-Warning "No .sops.yaml configuration found in '$Path'. Cannot determine encryption rules."
        return @()
    }

    # Extract unique file extensions from path_regex patterns (e.g., '\.yaml$' -> '*.yaml')
    $filePatterns = @($config.CreationRules | ForEach-Object {
        if ($_.PathRegex -match '\\\.([a-zA-Z0-9]+)\$\??$') {
            "*.$($matches[1])"
        }
    } | Select-Object -Unique)

    if ($filePatterns.Count -eq 0) {
        Write-Verbose "No file extensions found in path_regex patterns, defaulting to *.yaml"
        $filePatterns = @('*.yaml')
    }

    Write-Verbose "Searching for files matching patterns: $($filePatterns -join ', ')"

    # Find all files matching extracted patterns
    $files = @(
        foreach ($pattern in $filePatterns) {
            Get-ChildItem -Path $Path -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue
        }
    )

    if ($files.Count -eq 0) {
        Write-Verbose "No files found matching patterns: $($filePatterns -join ', ')"
        return @()
    }

    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $files) {
        if ($file.Name -eq '.sops.yaml') {
            continue
        }

        # Unencrypted suffix exclusion (cheapest operation)
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $hasUnencryptedSuffix = $false
        foreach ($suffix in $config.UnencryptedSuffixes) {
            if ($fileNameWithoutExt.EndsWith($suffix)) {
                $hasUnencryptedSuffix = $true
                break
            }
        }
        if ($hasUnencryptedSuffix) {
            continue
        }

        # Find first matching rule by path_regex (first match wins per SOPS spec)
        $matchingRule = $null
        foreach ($rule in $config.CreationRules) {
            if (Test-PathMatchesRegex -FilePath $file.FullName -VaultPath $Path -PathRegex $rule.PathRegex) {
                $matchingRule = $rule
                break
            }
        }

        if (-not $matchingRule) {
            continue
        }

        # Already encrypted check (fast streaming check)
        if (Test-SopsEncrypted -FilePath $file.FullName) {
            continue
        }

        # Content key matching (most expensive - YAML parsing)
        if ($matchingRule.EncryptedRegex) {
            if (-not (Test-FileContainsKeys -FilePath $file.FullName -EncryptedRegex $matchingRule.EncryptedRegex)) {
                continue
            }
        }

        $candidates.Add($file.FullName)
    }

    return [string[]]$candidates
}
