function Set-Secret {
    <#
    .SYNOPSIS
    Creates or updates a secret in the SOPS vault.

    .DESCRIPTION
    Creates a new SOPS-encrypted secret file or updates an existing one. When updating
    existing secrets, only the specified fields are changed, preserving all other data.

    String values can be provided in three formats:
    - Path syntax: ".stringData.password: newValue" - Updates a single nested field
    - YAML content: Multi-line YAML - Updates multiple fields from YAML structure
    - Plain string: Simple value stored in "value" key

    .PARAMETER Name
    The name of the secret. Can include namespace path (e.g., "apps/foo/bar/secret").

    .PARAMETER Secret
    The secret value. Can be String, SecureString, PSCredential, Hashtable, or Byte[].

    .PARAMETER VaultName
    The name of the registered vault.

    .PARAMETER AdditionalParameters
    Additional vault parameters (Path, FilePattern, etc.).

    .PARAMETER Metadata
    Optional metadata (not currently used).

    .OUTPUTS
    None. Throws errors on failure.

    .EXAMPLE
    Set-Secret -Name 'db-password' -Secret 'myPass123' -Vault 'MySopsVault'

    .EXAMPLE
    $k8sSecret = @{ stringData = @{ 'api-key' = 'secret' } }
    Set-Secret -Name 'apps/myapp/config' -Secret $k8sSecret -Vault 'MySopsVault'

    .EXAMPLE
    # Update a single nested field using path syntax
    ".stringData.password: newPassword" | Set-Secret -Name 'apps/web/prod/db' -Vault 'MySopsVault'

    .EXAMPLE
    # Patch multiple fields with YAML (preserves other existing fields)
    @"
    stringData:
      password: newPassword
      username: admin
    "@ | Set-Secret -Name 'apps/web/prod/db' -Vault 'MySopsVault'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [hashtable]$AdditionalParameters,

        [Parameter()]
        [hashtable]$Metadata
    )

    # 1. Validate SOPS availability
    if (-not (Test-SopsAvailable)) {
        throw "SOPS binary not found. Install from https://github.com/getsops/sops/releases"
    }

    # 2. Get and validate vault parameters
    try {
        $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters
        Assert-VaultPath -Parameters $params
    }
    catch {
        throw "Vault configuration error: $_"
    }

    # 3. Determine target file path
    # Convert secret name to file path (e.g., "apps/foo/secret" -> "{VaultPath}/apps/foo/secret.yaml")
    $fileName = $Name -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $filePath = Join-Path $params.Path "$fileName.yaml"

    # 4. Ensure directory exists
    $directory = [System.IO.Path]::GetDirectoryName($filePath)
    if (-not (Test-Path $directory)) {
        try {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        catch {
            throw "Failed to create directory '$directory': $_"
        }
    }

    # 5. Convert secret to YAML structure
    try {
        $newContent = ConvertTo-SecretYaml -Secret $Secret -Name $Name
    }
    catch {
        throw "Failed to convert secret '$Name': $_"
    }

    # 6. Check if file exists (patch-first vs new file)
    $fileExists = Test-Path $filePath

    if ($fileExists) {
        # PATCH-FIRST APPROACH: Use SOPS --set to update existing encrypted file
        try {
            # For string values, intelligently detect the update mode:
            # 1. Path-based syntax (.path.to.field: value)
            # 2. YAML content (multi-line YAML to patch)
            # 3. Plain string (store in 'value' key)
            if ($newContent -is [string]) {
                # Use new converter that handles all three string modes
                $setPaths = ConvertTo-SopsSetPathFromString -Secret $newContent

                foreach ($item in $setPaths) {
                    if ($null -eq $item.Value) {
                        # Use SOPS unset to completely remove the key
                        Invoke-SopsUnset -Path $item.Path -FilePath $filePath -VaultParameters $params | Out-Null
                    }
                    else {
                        # Escape quotes in value for set operation
                        $valueStr = if ($item.Value -eq '') {
                            # Empty string should be quoted
                            '""'
                        }
                        elseif ($item.Value -is [bool]) {
                            $item.Value.ToString().ToLower()
                        }
                        elseif ($item.Value -is [int] -or $item.Value -is [long] -or $item.Value -is [double]) {
                            $item.Value.ToString()
                        }
                        else {
                            # String value - wrap in quotes and escape
                            $escaped = $item.Value -replace '"', '\"'
                            "`"$escaped`""
                        }

                        $setExpression = "$($item.Path) $valueStr"
                        Invoke-SopsSet -SetExpression $setExpression -FilePath $filePath -VaultParameters $params | Out-Null
                    }
                }
            }
            else {
                # For hashtables, convert to set paths and update each key
                $setPaths = ConvertTo-SopsSetPath -Object $newContent

                foreach ($item in $setPaths) {
                    if ($null -eq $item.Value) {
                        # Use SOPS unset to completely remove the key
                        Invoke-SopsUnset -Path $item.Path -FilePath $filePath -VaultParameters $params | Out-Null
                    }
                    else {
                        # Escape quotes in value for set operation
                        $valueStr = if ($item.Value -is [bool]) {
                            $item.Value.ToString().ToLower()
                        }
                        elseif ($item.Value -is [int] -or $item.Value -is [long] -or $item.Value -is [double]) {
                            $item.Value.ToString()
                        }
                        else {
                            # String value - wrap in quotes and escape
                            $escaped = $item.Value -replace '"', '\"'
                            "`"$escaped`""
                        }

                        $setExpression = "$($item.Path) $valueStr"
                        Invoke-SopsSet -SetExpression $setExpression -FilePath $filePath -VaultParameters $params | Out-Null
                    }
                }
            }

            # Success - no return value needed
        }
        catch {
            throw "Failed to update existing secret '$Name': $_"
        }
    }
    else {
        # NEW FILE: Create and encrypt
        # To support path-based encryption rules, we must encrypt the file at its final location
        # so SOPS can correctly match path_regex patterns in .sops.yaml
        #
        # Strategy: Write plaintext to {filename}.insecure.yaml, encrypt in-place, then rename
        # This ensures SOPS uses the correct path for rule matching

        $insecureFilePath = $filePath -replace '\.yaml$', '.insecure.yaml'

        try {
            # Convert to YAML and write to insecure temp file at final location
            Import-Module powershell-yaml -ErrorAction Stop

            if ($newContent -is [string]) {
                # Plain string - wrap in a key-value structure (SOPS requires a map, not a scalar)
                $yamlContent = @{ value = $newContent } | ConvertTo-Yaml
            }
            else {
                $yamlContent = $newContent | ConvertTo-Yaml
            }

            Set-Content -Path $insecureFilePath -Value $yamlContent -NoNewline

            # Encrypt in-place so SOPS uses the actual file path for rule matching
            # SOPS will read .insecure.yaml path but we need it to match rules for .yaml
            # Use --config to explicitly specify the .sops.yaml location in the vault directory
            $sopsConfigPath = Join-Path $params.Path '.sops.yaml'

            # For path-based encryption to work, SOPS needs:
            # 1. File path relative to the .sops.yaml config file
            # 2. Working directory set to the vault root (where .sops.yaml lives)
            #
            # This ensures path_regex patterns in .sops.yaml match correctly
            # Example: path_regex: apps/prod/.*\.yaml$ matches apps/prod/keys.yaml

            if (Test-Path $sopsConfigPath) {
                # Rename to final location first
                Move-Item -Path $insecureFilePath -Destination $filePath -Force

                # Calculate relative path from vault root for SOPS path matching
                # SOPS matches paths relative to the .sops.yaml location
                # Keep platform-native path separators (backslashes on Windows, forward slashes on Linux/Mac)
                # because SOPS regex patterns must match the platform's path format
                $relativePath = [System.IO.Path]::GetRelativePath($params.Path, $filePath)

                # Save current location and change to vault root
                $previousLocation = Get-Location
                try {
                    Set-Location -Path $params.Path

                    # Encrypt in-place using relative path from vault root
                    # This allows path_regex patterns to match correctly
                    try {
                        Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $params
                    }
                    catch {
                        # Encryption failed - clean up the unencrypted file
                        $absolutePath = Join-Path $params.Path $relativePath
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
                Move-Item -Path $insecureFilePath -Destination $filePath -Force

                $relativePath = [System.IO.Path]::GetRelativePath($params.Path, $filePath)

                $previousLocation = Get-Location
                try {
                    Set-Location -Path $params.Path

                    try {
                        Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $params
                    }
                    catch {
                        # Encryption failed - clean up the unencrypted file
                        $absolutePath = Join-Path $params.Path $relativePath
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
            throw "Failed to create secret '$Name': $_"
        }
        finally {
            # Clean up insecure file if it still exists (shouldn't, but be safe)
            if (Test-Path $insecureFilePath) {
                Remove-Item $insecureFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
