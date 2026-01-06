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

    .PARAMETER VaultPath
    Path to the vault root directory containing .sops.yaml.

    .PARAMETER FilePattern
    File pattern to match (e.g., '*.yaml'). Defaults to '*.yaml'.

    .PARAMETER Recurse
    Whether to search subdirectories recursively. Defaults to $true.

    .OUTPUTS
    String[] - Array of absolute file paths that are candidates for encryption.

    .EXAMPLE
    Get-SopsEncryptionCandidates -VaultPath 'C:\secrets'
    # Returns: @('C:\secrets\config.yaml', 'C:\secrets\api-key.yaml')

    .EXAMPLE
    Get-SopsEncryptionCandidates -VaultPath '/vault' -FilePattern '*.yaml' -Recurse $true
    # Recursively scans /vault for unencrypted YAML files matching .sops.yaml rules

    .EXAMPLE
    # Migration workflow
    $candidates = Get-SopsEncryptionCandidates -VaultPath 'C:\secrets'
    foreach ($file in $candidates) {
        Write-Host "Encrypting: $file"
        sops --encrypt --in-place $file
    }

    .EXAMPLE
    # CI/CD validation
    $unencrypted = Get-SopsEncryptionCandidates -VaultPath $env:SECRETS_DIR
    if ($unencrypted.Count -gt 0) {
        throw "Security violation: Found unencrypted secret files"
    }

    .NOTES
    Requires .sops.yaml to exist in VaultPath. Returns empty array if not found.
    Uses 'sops filestatus' for reliable encryption detection.
    Requires SOPS binary to be available in PATH.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$VaultPath,

        [Parameter()]
        [string]$FilePattern = '*.yaml',

        [Parameter()]
        [bool]$Recurse = $true
    )

    # Import private functions
    $privateFunctionPath = Join-Path $PSScriptRoot '..' 'Private'
    . (Join-Path $privateFunctionPath 'Get-SopsConfiguration.ps1')
    . (Join-Path $privateFunctionPath 'Test-PathMatchesRegex.ps1')
    . (Join-Path $privateFunctionPath 'Test-FileContainsKeys.ps1')

    # Initialize result
    $candidates = @()

    # Check if .sops.yaml exists
    $config = Get-SopsConfiguration -VaultPath $VaultPath
    if (-not $config.Found) {
        Write-Warning "No .sops.yaml configuration found in '$VaultPath'. Cannot determine encryption rules."
        return @()
    }

    # Find all files matching pattern
    $findParams = @{
        Path        = $VaultPath
        Filter      = $FilePattern
        File        = $true
        Recurse     = $Recurse
        ErrorAction = 'SilentlyContinue'
    }

    try {
        $files = Get-ChildItem @findParams
    }
    catch {
        Write-Warning "Failed to enumerate files in '$VaultPath': $_"
        return @()
    }

    # Process each file
    foreach ($file in $files) {
        # Skip .sops.yaml itself
        if ($file.Name -eq '.sops.yaml') {
            continue
        }

        # Check 1: Unencrypted suffix exclusion (cheapest operation)
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $matchesSuffix = $false
        foreach ($suffix in $config.UnencryptedSuffixes) {
            if ($fileNameWithoutExt.EndsWith($suffix)) {
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
            if (Test-PathMatchesRegex -FilePath $file.FullName -VaultPath $VaultPath -PathRegex $rule.PathRegex) {
                $matchingRule = $rule
                break  # First match wins
            }
        }

        if (-not $matchingRule) {
            continue
        }

        # Check 3: Already encrypted? (moderate cost - shell invocation)
        try {
            $statusResult = & sops filestatus $file.FullName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $status = $statusResult | ConvertFrom-Json
                if ($status.encrypted -eq $true) {
                    continue  # Already encrypted, skip
                }
            }
        }
        catch {
            Write-Warning "Failed to check encryption status for '$($file.FullName)': $_"
            continue
        }

        # Check 4: Content key matching (most expensive - YAML parsing)
        if ($matchingRule.EncryptedRegex) {
            if (-not (Test-FileContainsKeys -FilePath $file.FullName -EncryptedRegex $matchingRule.EncryptedRegex)) {
                continue  # Doesn't contain matching keys
            }
        }

        # Passed all checks - it's a candidate!
        $candidates += $file.FullName
    }

    return $candidates
}
