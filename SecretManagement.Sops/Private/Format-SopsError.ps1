function Format-SopsError {
    <#
    .SYNOPSIS
    Formats SOPS error messages with context-aware troubleshooting hints.

    .DESCRIPTION
    Analyzes SOPS error output and provides helpful, actionable error messages
    with resolution steps based on common failure scenarios.

    .PARAMETER ErrorMessage
    The error message output from SOPS.

    .PARAMETER Operation
    The SOPS operation that failed (decrypt, encrypt, set).

    .PARAMETER VaultParameters
    Optional vault parameters for providing key configuration context.

    .OUTPUTS
    String - Formatted error message with troubleshooting guidance.

    .EXAMPLE
    Format-SopsError -ErrorMessage "az: command not found" -Operation "decrypt"
    # Returns detailed message about Azure CLI missing

    .EXAMPLE
    Format-SopsError -ErrorMessage "failed to get the data key" -Operation "decrypt" -VaultParameters @{ AgeKeyFile = 'C:\keys\vault.txt' }
    # Returns message with current key file configuration
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [Parameter(Mandatory)]
        [ValidateSet('decrypt', 'encrypt', 'set')]
        [string]$Operation,

        [Parameter()]
        [hashtable]$VaultParameters
    )

    # Check for Azure CLI missing
    if ($ErrorMessage -match 'az: command not found|az.cmd.*not recognized') {
        return @"
SOPS failed to $Operation`: Azure CLI ('az') not found in PATH.

Resolution:
  1. Install Azure CLI from https://learn.microsoft.com/cli/azure/install-azure-cli
  2. OR configure age encryption as fallback

See: https://github.com/getsops/sops#encrypting-using-azure-key-vault
"@
    }

    # Check for data key access failure
    if ($ErrorMessage -match 'failed to get the data key') {
        # Provide context about which key configuration was used
        $ageKeyHint = if ($VaultParameters -and $VaultParameters.AgeKeyFile) {
            "Current vault AgeKeyFile: $($VaultParameters.AgeKeyFile)"
        }
        elseif ($env:SOPS_AGE_KEY_FILE) {
            "Current SOPS_AGE_KEY_FILE: $env:SOPS_AGE_KEY_FILE"
        }
        else {
            "No age key file configured (neither vault parameter nor environment variable)"
        }

        return @"
SOPS failed to $Operation`: Unable to access encryption keys.

Configuration:
  $ageKeyHint

Resolution:
  1. Ensure you have access to the Azure Key Vault key
  2. OR configure age encryption with a valid key file
  3. Verify the key file exists and is readable

Error details: $ErrorMessage
"@
    }

    # Check for age key file configuration missing
    if ($ErrorMessage -match 'SOPS_AGE_KEY_FILE|age key') {
        return @"
SOPS failed to $Operation`: age key file not configured.

Resolution:
  1. Set vault AgeKeyFile parameter when registering vault:
     Register-SecretVault -VaultParameters @{ AgeKeyFile = 'C:\path\to\key.txt' }
  2. OR set SOPS_AGE_KEY_FILE environment variable

Error details: $ErrorMessage
"@
    }

    # Check for missing creation rules (encryption-specific)
    if ($Operation -eq 'encrypt' -and $ErrorMessage -match 'no matching creation rules|creation_rules') {
        return @"
SOPS failed to encrypt: No creation rules found.

Resolution:
  1. Create a .sops.yaml file in the vault directory
  2. Define creation rules for encryption (age, Azure Key Vault, etc.)

Example .sops.yaml:
  creation_rules:
    - path_regex: \.yaml$
      age: age1public_key_here

See: https://github.com/getsops/sops#using-sops-yaml-conf-to-select-kms-pgp-for-new-files

Error details: $ErrorMessage
"@
    }

    # Generic SOPS error with operation context
    return "SOPS $Operation failed: $ErrorMessage"
}
