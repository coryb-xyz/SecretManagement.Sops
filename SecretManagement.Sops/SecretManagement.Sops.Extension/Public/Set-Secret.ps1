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
    Optional metadata. Supports DocumentName key to target a specific document
    in multi-document YAML files by metadata.name.

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

    if (-not (Test-SopsAvailable)) {
        throw "SOPS binary not found. Install from https://github.com/getsops/sops/releases"
    }

    $params = Get-VaultParameters -AdditionalParameters $AdditionalParameters
    Assert-VaultPath -Parameters $params

    # Convert secret name to file path (e.g., "apps/foo/secret" -> "{VaultPath}/apps/foo/secret.yaml")
    $fileName = $Name -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $filePath = Join-Path $params.Path "$fileName.yaml"

    # Ensure parent directory exists
    $directory = [System.IO.Path]::GetDirectoryName($filePath)
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $newContent = ConvertTo-SecretYaml -Secret $Secret -Name $Name

    if (Test-Path $filePath) {
        Update-EncryptedSecret -FilePath $filePath -Content $newContent -VaultParameters $params -SecretName $Name -Metadata $Metadata
    }
    else {
        New-EncryptedSecretFile -FilePath $filePath -Content $newContent -VaultParameters $params -SecretName $Name
    }
}
