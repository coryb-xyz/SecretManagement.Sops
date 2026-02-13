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

    $insecureFilePath = $FilePath -replace '\.yaml$', '.insecure.yaml'

    try {
        Import-Module powershell-yaml -ErrorAction Stop

        $yamlContent = if ($Content -is [string]) {
            ConvertTo-HashtableFromSetPath -Secret $Content | ConvertTo-Yaml
        }
        else {
            $Content | ConvertTo-Yaml
        }

        Set-Content -Path $insecureFilePath -Value $yamlContent -NoNewline
        Move-Item -Path $insecureFilePath -Destination $FilePath -Force

        # SOPS needs a relative path from the vault root (where .sops.yaml lives)
        # so that path_regex patterns match correctly.
        $relativePath = [System.IO.Path]::GetRelativePath($VaultParameters.Path, $FilePath)

        Push-Location -Path $VaultParameters.Path
        try {
            Invoke-SopsEncrypt -FilePath $relativePath -InPlace -VaultParameters $VaultParameters
        }
        finally {
            Pop-Location
        }
    }
    catch {
        # Clean up the plaintext file on any failure (encryption or otherwise)
        Remove-Item $FilePath -Force -ErrorAction SilentlyContinue
        throw "Failed to create secret '$SecretName': $_"
    }
    finally {
        Remove-Item $insecureFilePath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-HashtableFromSetPath {
    <#
    .SYNOPSIS
    Converts a string secret into a hashtable via SOPS set-path parsing.

    .DESCRIPTION
    Parses a string through ConvertTo-SopsSetPathFromString to get structured
    path/value pairs, then reconstructs a nested hashtable suitable for YAML
    serialization. This handles path-based syntax, YAML strings, and plain
    strings uniformly.

    .PARAMETER Secret
    The string secret to convert.

    .OUTPUTS
    Hashtable representing the nested structure.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Secret
    )

    $setPaths = ConvertTo-SopsSetPathFromString -Secret $Secret
    $result = @{}

    foreach ($item in $setPaths) {
        $pathParts = $item.Path -replace '^\["|"\]$', '' -split '"\]\["'
        $current = $result

        for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
            if (-not $current.ContainsKey($pathParts[$i])) {
                $current[$pathParts[$i]] = @{}
            }
            $current = $current[$pathParts[$i]]
        }

        $current[$pathParts[-1]] = $item.Value
    }

    return $result
}
