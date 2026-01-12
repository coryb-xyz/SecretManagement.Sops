function Update-EncryptedSecret {
    <#
    .SYNOPSIS
    Updates an existing SOPS-encrypted secret file using patch operations.

    .DESCRIPTION
    Uses SOPS --set and --unset to update specific fields in an existing encrypted
    secret file without decrypting and re-encrypting the entire file. Supports both
    string and hashtable content.

    For string values, intelligently detects the update mode:
    - Path-based syntax (.path.to.field: value)
    - YAML content (multi-line YAML to patch)
    - Plain string (stored in 'value' key)

    .PARAMETER FilePath
    The path to the existing encrypted secret file.

    .PARAMETER Content
    The content to update. Can be a string or hashtable.

    .PARAMETER VaultParameters
    Vault configuration parameters.

    .PARAMETER SecretName
    The name of the secret (used for error messages).

    .OUTPUTS
    None. Throws errors on failure.

    .EXAMPLE
    Update-EncryptedSecret -FilePath 'C:\vault\secret.yaml' -Content '.password: newPass' -VaultParameters $params -SecretName 'db'

    .EXAMPLE
    $content = @{ stringData = @{ password = 'newPass' } }
    Update-EncryptedSecret -FilePath 'C:\vault\secret.yaml' -Content $content -VaultParameters $params -SecretName 'api'
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

    try {
        # For string values, intelligently detect the update mode:
        # 1. Path-based syntax (.path.to.field: value)
        # 2. YAML content (multi-line YAML to patch)
        # 3. Plain string (store in 'value' key)
        if ($Content -is [string]) {
            # Use converter that handles all three string modes
            $setPaths = ConvertTo-SopsSetPathFromString -Secret $Content

            foreach ($item in $setPaths) {
                if ($null -eq $item.Value) {
                    # Use SOPS unset to completely remove the key
                    Invoke-SopsUnset -Path $item.Path -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
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
                    Invoke-SopsSet -SetExpression $setExpression -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
                }
            }
        }
        else {
            # For hashtables, convert to set paths and update each key
            $setPaths = ConvertTo-SopsSetPath -Object $Content

            foreach ($item in $setPaths) {
                if ($null -eq $item.Value) {
                    # Use SOPS unset to completely remove the key
                    Invoke-SopsUnset -Path $item.Path -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
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
                    Invoke-SopsSet -SetExpression $setExpression -FilePath $FilePath -VaultParameters $VaultParameters | Out-Null
                }
            }
        }

        # Success - no return value needed
    }
    catch {
        throw "Failed to update existing secret '$SecretName': $_"
    }
}
