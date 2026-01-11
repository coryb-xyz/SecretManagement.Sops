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
    Uses 'sops filestatus' for reliable encryption detection.
    Requires SOPS binary to be available in PATH.
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

    # Initialize result
    $candidates = @()

    # Check if .sops.yaml exists
    $config = Get-SopsConfiguration -VaultPath $Path
    if (-not $config.Found) {
        Write-Warning "No .sops.yaml configuration found in '$Path'. Cannot determine encryption rules."
        return @()
    }

    # Extract file patterns from creation_rules
    $candidateFilePatterns = @()
    foreach ($rule in $config.CreationRules) {
        # Extract file extension from path_regex (e.g., '\.yaml$' -> '*.yaml')
        if ($rule.PathRegex -match '\\\.([a-zA-Z0-9]+)\$\??$') {
            $extension = $matches[1]
            $pattern = "*.$extension"
            if ($candidateFilePatterns -notcontains $pattern) {
                $candidateFilePatterns += $pattern
            }
        }
    }

    # Fallback to *.yaml if no patterns extracted
    if ($candidateFilePatterns.Count -eq 0) {
        Write-Verbose "No file extensions found in path_regex patterns, defaulting to *.yaml"
        $candidateFilePatterns = @('*.yaml')
    }

    Write-Verbose "Searching for files matching patterns: $($candidateFilePatterns -join ', ')"

    # Find all files matching extracted patterns
    $allFiles = @()
    foreach ($pattern in $candidateFilePatterns) {
        $findParams = @{
            Path        = $Path
            Filter      = $pattern
            File        = $true
            Recurse     = $true  # Always recurse
            ErrorAction = 'SilentlyContinue'
        }

        try {
            $allFiles += @(Get-ChildItem @findParams)
        }
        catch {
            Write-Warning "Failed to enumerate files matching '$pattern' in '$Path': $_"
        }
    }

    if ($allFiles.Count -eq 0) {
        Write-Verbose "No files found matching patterns: $($candidateFilePatterns -join ', ')"
        return @()
    }

    $candidateFiles = $allFiles

    # Process each file
    foreach ($candidateFile in $candidateFiles) {
        # Skip .sops.yaml itself
        if ($candidateFile.Name -eq '.sops.yaml') {
            continue
        }

        # Check 1: Unencrypted suffix exclusion (cheapest operation)
        $candidateFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($candidateFile.Name)
        $matchesSuffix = $false
        foreach ($suffix in $config.UnencryptedSuffixes) {
            if ($candidateFileNameWithoutExt.EndsWith($suffix)) {
                $matchesSuffix = $true
                break
            }
        }
        if ($matchesSuffix) {
            continue
        }

        # Check 2: Find first matching rule by path_regex
        $matchingRule = $null
        foreach ($rule in $config.CreationRules) {
            if (Test-PathMatchesRegex -FilePath $candidateFile.FullName -VaultPath $Path -PathRegex $rule.PathRegex) {
                $matchingRule = $rule
                break  # First match wins
            }
        }

        if (-not $matchingRule) {
            continue
        }

        # Check 3: Already encrypted? (moderate cost - shell invocation)
        try {
            $statusResult = & sops filestatus $candidateFile.FullName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $status = $statusResult | ConvertFrom-Json
                if ($status.encrypted -eq $true) {
                    continue  # Already encrypted, skip
                }
            }
        }
        catch {
            Write-Warning "Failed to check encryption status for '$($candidateFile.FullName)': $_"
            continue
        }

        # Check 4: Content key matching (most expensive - YAML parsing)
        if ($matchingRule.EncryptedRegex) {
            if (-not (Test-FileContainsKeys -FilePath $candidateFile.FullName -EncryptedRegex $matchingRule.EncryptedRegex)) {
                continue  # Doesn't contain matching keys
            }
        }

        # Passed all checks - it's a candidate!
        $candidates += $candidateFile.FullName
    }

    return $candidates
}
