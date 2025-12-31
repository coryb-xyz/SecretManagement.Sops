# SecretManagement.Sops

A PowerShell SecretManagement extension vault for [Mozilla SOPS](https://github.com/getsops/sops) (Secrets OPerationS). Provides native PowerShell integration for SOPS-encrypted secrets with support for Azure Key Vault, age, and Kubernetes Secret manifests.

## Overview

SecretManagement.Sops enables PowerShell developers to work with SOPS-encrypted secrets using the familiar `Get-Secret`, `Get-SecretInfo`, and other SecretManagement cmdlets. It's designed for DevOps teams using GitOps workflows.

### Key Features

- **Native PowerShell Integration**: Use `Get-Secret` and other SecretManagement cmdlets with SOPS
- **Namespace Support**: Folder-based namespacing with collision detection for duplicate secret names
- **Multiple Encryption Backends**: Supports Azure Key Vault, age, AWS KMS, GCP KMS, and PGP
- **FluxCD Compatible**: Works alongside existing SOPS and FluxCD workflows
- **Cross-Platform**: Windows PowerShell 5.1 and PowerShell 7+ on Windows, Linux, and macOS

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Vault Parameters](#vault-parameters)
- [Kubernetes Secret Support](#kubernetes-secret-support)
- [Namespace Support and Collision Detection](#namespace-support-and-collision-detection)
- [Write Operations](#write-operations)
- [Troubleshooting](#troubleshooting)
- [Current Limitations](#current-limitations)
- [Roadmap](#roadmap)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## Requirements

- **PowerShell**: 5.1 or later (PowerShell 7+ recommended)
- **Microsoft.PowerShell.SecretManagement**: 1.1.0 or later
- **SOPS**: Binary must be installed and available in PATH ([download](https://github.com/getsops/sops/releases))
- **Encryption Backend**: One of the following:
  - Azure CLI (for Azure Key Vault)
  - age key file (for age encryption)
  - AWS credentials (for AWS KMS)
  - GCP credentials (for GCP KMS)
  - GPG (for PGP)

## Installation

### 1. Install SecretManagement Module

```powershell
Install-Module -Name Microsoft.PowerShell.SecretManagement -Repository PSGallery
```

### 2. Install SOPS

Download and install SOPS from: https://github.com/getsops/sops/releases

Verify installation:
```powershell
sops --version
```

### 3. Install SecretManagement.Sops

**Manual Installation (Source):**

Download or clone this repository, then import the module:

```powershell
# Import from source (for development)
Import-Module .\SecretManagement.Sops\SecretManagement.Sops.psd1
```

**Manual Installation (Built):**

For production use, build and install the compiled module:

```powershell
# Build the module
.\build.ps1 -Task Build

# Import the built module
Import-Module .\Build\SecretManagement.Sops\SecretManagement.Sops.psd1
```

**PowerShell Gallery (Coming Soon):**

```powershell
Install-Module -Name SecretManagement.Sops -Repository PSGallery
```

### 4. Set Up Encryption Keys

**For age encryption (recommended for testing):**

```bash
# Generate an age key
age-keygen -o ~/.sops/key.txt

# Set environment variable
$env:SOPS_AGE_KEY_FILE = "$HOME\.sops\key.txt"
```

**For Azure Key Vault:**

```powershell
# Authenticate with Azure CLI
az login

# Ensure you have access to the Key Vault key
az keyvault key show --vault-name <vault-name> --name <key-name>
```

## Quick Start

### Register a Vault

```powershell
Register-SecretVault -Name 'GitOpsSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\infrastructure\secrets'
    FilePattern = '*.yaml'
    Recurse = $true
}
```

### List Available Secrets

```powershell
# List all secrets
Get-SecretInfo -Vault 'GitOpsSecrets'

# Filter by pattern
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter 'database/*'
```

### Retrieve Secrets

```powershell
# Get a simple secret as SecureString
$dbPassword = Get-Secret -Name 'database/password' -Vault 'GitOpsSecrets'

# Get as plain text (use with caution!)
$apiKey = Get-Secret -Name 'api/key' -Vault 'GitOpsSecrets' -AsPlainText

# Get a Kubernetes Secret data key
$licenseKey = Get-Secret -Name 'software-license/license-key' -Vault 'GitOpsSecrets' -AsPlainText

# Get full Kubernetes Secret manifest
$manifest = Get-Secret -Name 'software-license' -Vault 'GitOpsSecrets' -AsPlainText
```

### PSCredential Support

If a secret has `username` and `password` keys, it's automatically returned as a `PSCredential`:

```powershell
# YAML file contains:
# username: admin
# password: MyPassword123

$cred = Get-Secret -Name 'admin-credentials' -Vault 'GitOpsSecrets'
$cred.UserName  # Returns: admin
```

## Vault Parameters

Configure vault behavior with these parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Path` | String | **Required** | Directory containing SOPS-encrypted files |
| `FilePattern` | String | `*.yaml` | File pattern to match (e.g., `*.yml`, `*.json`) |
| `Recurse` | Boolean | `$false` | Search subdirectories recursively |
| `NamingStrategy` | String | `RelativePath` | How to name secrets: `RelativePath`, `FileName`, or `KubernetesMetadata` |
| `KubernetesMode` | Boolean | `$true` | Enable Kubernetes Secret detection and intelligent filtering |

### Naming Strategies

**RelativePath (Default)**
```
File: C:\secrets\database\postgres.yaml
Secret Name: database/postgres
```

**FileName**
```
File: C:\secrets\nested\deep\config.yaml
Secret Name: config
```

**KubernetesMetadata**
```
File: C:\secrets\app\secret.yaml
K8s metadata.name: my-app-secret
Secret Name: my-app-secret
```

### Example: Custom Configuration

```powershell
Register-SecretVault -Name 'ProductionSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\infra\secrets\production'
    FilePattern = '*.yaml'
    Recurse = $true
    NamingStrategy = 'KubernetesMetadata'
    KubernetesMode = $true
}
```

## Kubernetes Secret Support

SecretManagement.Sops provides special handling for Kubernetes Secret manifests:

### Example Kubernetes Secret (SOPS-encrypted)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: software-license
  namespace: myapp
type: Opaque
stringData:
  license-key: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
  admin-password: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
sops:
  # SOPS metadata...
```

### Accessing Kubernetes Secrets

The module intelligently filters Kubernetes Secrets based on your `.sops.yaml` configuration. For example, with `encrypted_regex: ^(data|stringData)$`, only the actual secret data is returned:

```powershell
# Get secret data (returns only encrypted fields based on .sops.yaml)
$secretData = Get-Secret -Name 'software-license' -Vault 'GitOpsSecrets' -AsPlainText

# Returns a hashtable with just the secret keys:
# @{
#   'license-key' = 'MC2L1C3NS3K3Y'
#   'admin-password' = 'SuperSecret123'
# }

# Access individual keys from the returned hashtable
$licenseKey = $secretData['license-key']
```

**Important**: Configure `.sops.yaml` with `encrypted_regex: ^(data|stringData)$` to encrypt only the secret data, not the Kubernetes metadata fields.

## Namespace Support and Collision Detection

SecretManagement.Sops provides folder-based namespace support to organize secrets and prevent collisions when multiple secrets have the same filename.

### How Namespaces Work

Namespaces are automatically derived from the folder structure relative to the vault root:

```
Vault Path: C:\secrets\

File: C:\secrets\apps\foo\bar\dv1\secret.yaml
→ Namespace: apps/foo/bar/dv1
→ Short Name: secret
→ Full Name: apps/foo/bar/dv1/secret

File: C:\secrets\database\postgres.yaml
→ Namespace: database
→ Short Name: postgres
→ Full Name: database/postgres

File: C:\secrets\api-key.yaml (at vault root)
→ Namespace: (empty)
→ Short Name: api-key
→ Full Name: api-key
```

### Accessing Secrets by Full Path

Use the full path to access secrets (recommended):

```powershell
# Access deeply nested secret
$secret = Get-Secret -Name 'apps/foo/bar/dv1/secret' -Vault 'GitOpsSecrets' -AsPlainText

# Access single-level namespace
$db = Get-Secret -Name 'database/postgres' -Vault 'GitOpsSecrets' -AsPlainText

# Access root-level secret
$apiKey = Get-Secret -Name 'api-key' -Vault 'GitOpsSecrets' -AsPlainText
```

### Short Name Access (Backward Compatible)

When no namespace collisions exist, you can use short names:

```powershell
# This works if only one 'postgres' exists in the vault
$db = Get-Secret -Name 'postgres' -Vault 'GitOpsSecrets' -AsPlainText
```

### Collision Detection

When multiple secrets share the same short name, you must use the full path:

```
Vault Structure:
  C:\secrets\apps\foo\bar\dv1\secret.yaml
  C:\secrets\apps\baz\prod\secret.yaml

# This will fail with a helpful error:
Get-Secret -Name 'secret' -Vault 'GitOpsSecrets'

Error: Multiple secrets with short name 'secret' found:
  - apps/foo/bar/dv1/secret (C:\secrets\apps\foo\bar\dv1\secret.yaml)
  - apps/baz/prod/secret (C:\secrets\apps\baz\prod\secret.yaml)

Please specify the full path.
Example: Get-Secret -Name 'apps/foo/bar/dv1/secret'

# Use the full path instead:
Get-Secret -Name 'apps/foo/bar/dv1/secret' -Vault 'GitOpsSecrets'
```

### Wildcard Filters with Namespaces

Filter secrets by namespace using wildcards:

```powershell
# List all secrets in a specific namespace
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter 'apps/foo/*'

# List all secrets in top-level namespace
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter 'database/*'

# List all secrets
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter '*'
```

### Namespace Metadata

Secret metadata includes namespace information:

```powershell
$info = Get-SecretInfo -Name 'apps/foo/bar/dv1/secret' -Vault 'GitOpsSecrets'

$info.Name                    # apps/foo/bar/dv1/secret (full path)
$info.Metadata.Namespace      # apps/foo/bar/dv1
$info.Metadata.ShortName      # secret
$info.Metadata.FilePath       # C:\secrets\apps\foo\bar\dv1\secret.yaml
```

### Kubernetes Secrets with Namespaces

Kubernetes secrets work seamlessly with namespace support:

```powershell
# Get full K8s secret (returns hashtable with all data keys)
$k8s = Get-Secret -Name 'apps/foo/bar/dv1/myapp' -Vault 'GitOpsSecrets' -AsPlainText
$k8s.stringData.Keys  # Lists: license-key, config, etc.

# Extract specific data key
$license = Get-Secret -Name 'apps/foo/bar/dv1/myapp/license-key' -Vault 'GitOpsSecrets' -AsPlainText
```

## Write Operations

SecretManagement.Sops provides full write support for creating, updating, and deleting secrets.

### Set-Secret (Create/Update)

Use `Set-Secret` to create new secrets or update existing ones:

```powershell
# Create a new simple secret
Set-Secret -Name 'api/key' -Vault 'GitOpsSecrets' -Secret 'my-api-key-123'

# Update an existing secret
Set-Secret -Name 'database/password' -Vault 'GitOpsSecrets' -Secret 'NewPassword123!'

# Set a PSCredential
$cred = Get-Credential
Set-Secret -Name 'admin-credentials' -Vault 'GitOpsSecrets' -Secret $cred

# Create a Kubernetes Secret with multiple keys
$secretData = @{
    'license-key' = 'ABC-123-DEF-456'
    'config.json' = '{"setting": "value"}'
}
Set-Secret -Name 'app/config' -Vault 'GitOpsSecrets' -Secret $secretData
```

**How it works:**
- **Existing files**: Uses a patch-first approach with `sops set` to preserve file structure and comments
- **New secrets**: Creates new SOPS-encrypted YAML files with appropriate encryption configuration
- **Kubernetes Secrets**: Automatically detects and properly structures Kubernetes Secret manifests

### Remove-Secret (Delete)

Use `Remove-Secret` to delete secrets:

```powershell
# Delete a simple secret (deletes the entire file)
Remove-Secret -Name 'api/old-key' -Vault 'GitOpsSecrets'

# Delete a specific key from a Kubernetes Secret
Remove-Secret -Name 'app/config/old-setting' -Vault 'GitOpsSecrets'
```

**Important Notes:**
- Deleting a simple secret removes the entire YAML file
- For Kubernetes Secrets with multiple data keys, only the specified key is removed
- The file remains SOPS-encrypted after updates
- Original file structure and comments are preserved when possible

## Troubleshooting

### SOPS Not Found

**Error**: `SOPS binary not found in PATH`

**Resolution**:
1. Install SOPS from https://github.com/getsops/sops/releases
2. Ensure the SOPS binary is in your PATH
3. Verify with: `sops --version`

### Azure CLI Issues (Windows)

**Error**: `Azure CLI ('az') not found in PATH`

**Resolution**:

**Option 1**: Install 32-bit Azure CLI (workaround for known SOPS issue on Windows)
```powershell
# Download and install 32-bit Azure CLI
# https://aka.ms/installazurecliwindows
```

**Option 2**: Use service principal authentication
```powershell
$env:AZURE_CLIENT_ID = 'your-client-id'
$env:AZURE_CLIENT_SECRET = 'your-client-secret'
$env:AZURE_TENANT_ID = 'your-tenant-id'
```

**Option 3**: Use age encryption as fallback
```powershell
# Add age key to .sops.yaml
$env:SOPS_AGE_KEY_FILE = "$HOME\.sops\key.txt"
```

### age Key Not Configured

**Error**: `SOPS failed to decrypt: age key file not configured`

**Resolution**:
```powershell
# Set the age key file environment variable
$env:SOPS_AGE_KEY_FILE = "C:\Users\YourName\.sops\key.txt"

# Make it persistent (add to PowerShell profile)
Add-Content $PROFILE "`n`$env:SOPS_AGE_KEY_FILE = 'C:\Users\YourName\.sops\key.txt'"
```

### Key Access Denied

**Error**: `Azure Key Vault access denied for key 'sops'`

**Resolution**:
1. Verify your Azure identity has `decrypt` and `encrypt` permissions on the key
2. Check with: `az keyvault key show --vault-name <vault> --name <key>`
3. Grant permissions: `az keyvault set-policy --name <vault> --upn <user> --key-permissions decrypt encrypt`

### No Secrets Found

**Warning**: `No SOPS files found matching pattern '*.yaml'`

**Resolution**:
1. Verify the `Path` parameter points to the correct directory
2. Check that SOPS-encrypted files exist with the specified pattern
3. Use `Recurse = $true` if files are in subdirectories
4. Try a different `FilePattern` (e.g., `*.yml`, `*secret*.yaml`)

## Current Limitations

- **YAML Only**: JSON and dotenv format support planned for future releases
- **No Caching**: Every operation invokes the SOPS binary (may impact performance for large vaults)
- **No Unlock-SecretVault**: Credential pre-caching not yet implemented

## Roadmap

### Completed Features (v0.3.0)
- ✅ Full read/write support (Get-Secret, Set-Secret, Remove-Secret)
- ✅ Kubernetes Secret manifest support
- ✅ Namespace support with collision detection
- ✅ Multiple naming strategies (RelativePath, FileName, KubernetesMetadata)
- ✅ Multiple encryption backends (Azure KV, age, AWS KMS, GCP KMS, PGP)

### Planned Features
- **Enhanced Format Support**: JSON and dotenv file formats
- **Performance Optimization**: In-memory caching with TTL for frequently accessed secrets
- **Credential Management**: `Unlock-SecretVault` for credential pre-caching and batch operations
- **Advanced Features**: File watcher for automatic index refresh, binary file support
- **PowerShell Gallery**: Official publication and versioning

## Examples

### Example 1: Local Development Secrets

```powershell
# One-time setup
Register-SecretVault -Name 'DevSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = '.\secrets'
}

# Daily usage
$dbConn = Get-Secret -Name 'database/connection-string' -Vault 'DevSecrets' -AsPlainText
$apiKey = Get-Secret -Name 'api/stripe-key' -Vault 'DevSecrets' -AsPlainText
```

### Example 2: CI/CD Pipeline

```powershell
# Azure DevOps Pipeline
$env:AZURE_CLIENT_ID = '$(ServicePrincipalId)'
$env:AZURE_CLIENT_SECRET = '$(ServicePrincipalSecret)'
$env:AZURE_TENANT_ID = '$(TenantId)'

Register-SecretVault -Name 'PipelineSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = '$(Build.SourcesDirectory)/secrets'
}

$deploymentKey = Get-Secret -Name 'deployment/ssh-key' -Vault 'PipelineSecrets' -AsPlainText
```

### Example 3: Export Secrets to .env File

```powershell
# Export all secrets to .env format for local development
Get-SecretInfo -Vault 'GitOpsSecrets' | ForEach-Object {
    $name = $_.Name.ToUpper().Replace('/', '_')
    $value = Get-Secret -Name $_.Name -Vault 'GitOpsSecrets' -AsPlainText
    "$name=$value"
} | Set-Content .env.local
```

### Example 4: Compare Secrets Across Vaults

```powershell
# Drift detection: Compare SOPS vault with Azure Key Vault
$sopsSecret = Get-Secret -Name 'api-key' -Vault 'GitOpsSops' -AsPlainText
$akvSecret = Get-Secret -Name 'api-key' -Vault 'AzureKeyVault' -AsPlainText

if ($sopsSecret -ne $akvSecret) {
    Write-Warning "Secret drift detected for 'api-key'!"
}
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Clone the repository
2. Install development dependencies:
   ```powershell
   # Run the automated dependency installer
   .\Install-SopsVaultDependencies.ps1 -IncludeDevelopment
   ```
3. Run the build:
   ```powershell
   # Full build with tests
   .\build.ps1 -Task Build

   # Quick iteration without tests
   .\build.ps1 -Task Quick
   ```

See [docs/Building.md](docs/Building.md) for detailed build documentation.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Mozilla SOPS](https://github.com/getsops/sops) - The excellent secrets encryption tool
- [PowerShell SecretManagement](https://github.com/PowerShell/SecretManagement) - The extensible secrets management framework
- [age](https://github.com/FiloSottile/age) - Simple, modern, and secure file encryption
- [FluxCD](https://fluxcd.io/) - GitOps continuous delivery

## Support

- **Documentation**: See [docs/requirements.md](docs/requirements.md) for detailed specifications
- **Testing Guide**: See [docs/TESTING-GUIDE.md](docs/TESTING-GUIDE.md) for interactive testing walkthrough
- **Dependencies**: See [DEPENDENCIES.md](DEPENDENCIES.md) for dependency management

---

**Version**: 0.3.0 - Full read/write support with Kubernetes Secret integration
