function New-EncryptedSecretFile {
    <#
    .SYNOPSIS
    Creates a new SOPS-encrypted secret file.

    .DESCRIPTION
    Creates a new encrypted secret file at the specified location. To support
    path-based encryption rules, the file is encrypted at its final location so
    SOPS can correctly match path_regex patterns in .sops.yaml.

    Strategy: Write plaintext to {filename}.insecure.yaml, rename to final location,
    encrypt in-place from vault root. This ensures SOPS uses the correct path for
    rule matching.

    .PARAMETER FilePath
    The path where the encrypted secret file should be created.

    .PARAMETER Content
    The content to encrypt. Can be a string or hashtable.

    .PARAMETER VaultParameters
    Vault configuration parameters (must include Path).

    .PARAMETER SecretName
    The name of the secret (used for error messages).

    .OUTPUTS
    None. Throws errors on failure.

    .EXAMPLE
    New-EncryptedSecretFile -FilePath 'C:\vault\apps\prod\secret.yaml' -Content $data -VaultParameters $params -SecretName 'db-creds'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [object]$Content,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters,

        [Parameter(Mandatory)]
        [string]$SecretName
    )

    # Use .insecure.yaml extension for temporary plaintext file
    $insecureFilePath = $FilePath -replace '\.yaml$', '.insecure.yaml'

    try {
        # Convert to YAML and write to insecure temp file at final location
        Import-Module powershell-yaml -ErrorAction Stop

        if ($Content -is [string]) {
            # Parse path-based syntax into setPaths
            $setPaths = ConvertTo-SopsSetPathFromString -Secret $Content

            # Reconstruct hashtable from setPaths
            $contentHash = @{}
            foreach ($item in $setPaths) {
                $pathParts = $item.Path -replace '^\["|"\]$', '' -split '"\]\["'
                $current = $contentHash
                for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
                    if (-not $current.ContainsKey($pathParts[$i])) {
                        $current[$pathParts[$i]] = @{}
                    }
                    $current = $current[$pathParts[$i]]
                }
                $current[$pathParts[-1]] = $item.Value
            }

            $yamlContent = $contentHash | ConvertTo-Yaml
        }
        else {
            $yamlContent = $Content | ConvertTo-Yaml
        }

        Set-Content -Path $insecureFilePath -Value $yamlContent -NoNewline

        # Encrypt in-place so SOPS uses the actual file path for rule matching
        # For path-based encryption to work, SOPS needs:
        # 1. File path relative to the .sops.yaml config file
        # 2. Working directory set to the vault root (where .sops.yaml lives)
        #
        # This ensures path_regex patterns in .sops.yaml match correctly
        # Example: path_regex: apps/prod/.*\.yaml$ matches apps/prod/keys.yaml

        $sopsConfigPath = Join-Path $VaultParameters.Path '.sops.yaml'

        if (Test-Path $sopsConfigPath) {
            # Rename to final location first
            Move-Item -Path $insecureFilePath -Destination $FilePath -Force

            # Calculate relative path from vault root for SOPS path matching
            # SOPS matches paths relative to the .sops.yaml location
            # Keep platform-native path separators (backslashes on Windows, forward slashes on Linux/Mac)
            # because SOPS regex patterns must match the platform's path format
            $relativePath = [System.IO.Path]::GetRelativePath($VaultParameters.Path, $FilePath)

            # Save current location and change to vault root
            $previousLocation = Get-Location
            try {
                Set-Location -Path $VaultParameters.Path

                # Encrypt in-place using relative path from vault root
                # This allows path_regex patterns to match correctly
                try {
                    Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $VaultParameters
                }
                catch {
                    # Encryption failed - clean up the unencrypted file
                    $absolutePath = Join-Path $VaultParameters.Path $relativePath
                    if (Test-Path $absolutePath) {
                        Remove-Item $absolutePath -Force -ErrorAction SilentlyContinue
                    }
                    throw
                }
            }
            finally {
                # Restore original location
                Set-Location -Path $previousLocation
            }
        }
        else {
            # Fallback to default config discovery if no .sops.yaml in vault
            # Same approach: rename then encrypt in-place from vault root
            Move-Item -Path $insecureFilePath -Destination $FilePath -Force

            $relativePath = [System.IO.Path]::GetRelativePath($VaultParameters.Path, $FilePath)

            $previousLocation = Get-Location
            try {
                Set-Location -Path $VaultParameters.Path

                try {
                    Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $VaultParameters
                }
                catch {
                    # Encryption failed - clean up the unencrypted file
                    $absolutePath = Join-Path $VaultParameters.Path $relativePath
                    if (Test-Path $absolutePath) {
                        Remove-Item $absolutePath -Force -ErrorAction SilentlyContinue
                    }
                    throw
                }
            }
            finally {
                Set-Location -Path $previousLocation
            }
        }

        # Success - file is now encrypted at final location
    }
    catch {
        throw "Failed to create secret '$SecretName': $_"
    }
    finally {
        # Clean up insecure file if it still exists (shouldn't, but be safe)
        if (Test-Path $insecureFilePath) {
            Remove-Item $insecureFilePath -Force -ErrorAction SilentlyContinue
        }
    }
}
