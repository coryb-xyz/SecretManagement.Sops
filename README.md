# SecretManagement.Sops

![Build Status](https://github.com/coryb-xyz/SecretManagement.Sops/workflows/CI/badge.svg)
![GitHub Release](https://img.shields.io/github/v/release/coryb-xyz/SecretManagement.Sops)
![License](https://img.shields.io/github/license/coryb-xyz/SecretManagement.Sops)
![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-Coming%20Soon-blue)

A PowerShell SecretManagement extension vault for [Mozilla SOPS](https://github.com/getsops/sops) (Secrets OPerationS). Provides native PowerShell integration for SOPS-encrypted secrets with support for Azure Key Vault, age, and Kubernetes Secret manifests.

## Overview

SecretManagement.Sops enables PowerShell developers to work with SOPS-encrypted secrets using the familiar `Get-Secret`, `Get-SecretInfo`, and other SecretManagement cmdlets. It's designed for DevOps teams using GitOps workflows.

### Key Features

- **Native PowerShell Integration**: Use `Get-Secret` and other SecretManagement cmdlets with SOPS
- **Namespace Support**: Folder-based namespacing with collision detection for duplicate secret names
- **Multiple Encryption Backends**: Supports Azure Key Vault, age, AWS KMS, GCP KMS, and PGP
- **Flexible Filtering**: Filter secrets by pattern and encryption status for controlled secret access


## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
  - [From GitHub Releases](#from-github-releases-recommended)
  - [From Source](#from-source)
  - [Upgrading](#upgrading)
  - [Uninstalling](#uninstalling)
- [Quick Start](#quick-start)
- [Vault Parameters](#vault-parameters)
- [Namespace Support and Collision Detection](#namespace-support-and-collision-detection)
- [Filtering and Encryption Control](#filtering-and-encryption-control)
- [Write Operations](#write-operations)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Current Limitations](#current-limitations)
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

### Prerequisites

Before installing SecretManagement.Sops, ensure you have:

1. **PowerShell**: Version 5.1 or later (PowerShell 7+ recommended)
2. **Microsoft.PowerShell.SecretManagement**: The SecretManagement framework

```powershell
Install-Module -Name Microsoft.PowerShell.SecretManagement -Repository PSGallery -Scope CurrentUser
```

3. **SOPS**: The encryption tool must be installed and available in PATH

Download and install SOPS from: https://github.com/getsops/sops/releases

Verify installation:
```powershell
sops --version
```

### From GitHub Releases (Recommended)

Download the latest release from: https://github.com/coryb-xyz/SecretManagement.Sops/releases

**PowerShell 7+ (recommended):**
```powershell
# Download the latest release ZIP file, then extract to your modules directory
$modulePath = "$HOME\Documents\PowerShell\Modules"
Expand-Archive -Path .\SecretManagement.Sops-v0.4.4.zip -DestinationPath $modulePath

# Verify installation
Get-Module -ListAvailable SecretManagement.Sops
```

**Windows PowerShell 5.1:**
```powershell
# Extract to WindowsPowerShell modules directory
$modulePath = "$HOME\Documents\WindowsPowerShell\Modules"
Expand-Archive -Path .\SecretManagement.Sops-v0.4.4.zip -DestinationPath $modulePath

# Verify installation
Get-Module -ListAvailable SecretManagement.Sops
```

**Quick one-liner installation (PowerShell 7+):**
```powershell
# Download and install latest release automatically
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/coryb-xyz/SecretManagement.Sops/releases/latest'
$zipUrl = $release.assets[0].browser_download_url
Invoke-WebRequest -Uri $zipUrl -OutFile "$env:TEMP\SecretManagement.Sops.zip"
Expand-Archive -Path "$env:TEMP\SecretManagement.Sops.zip" -DestinationPath "$HOME\Documents\PowerShell\Modules" -Force
Remove-Item "$env:TEMP\SecretManagement.Sops.zip"
```

### From Source

For development or if you want to build from source:

**Development (direct import):**
```powershell
# Clone the repository
git clone https://github.com/coryb-xyz/SecretManagement.Sops.git
cd SecretManagement.Sops

# Import from source
Import-Module .\SecretManagement.Sops\SecretManagement.Sops.psd1 -Force
```

**Production build:**
```powershell
# Build the module
.\build.ps1 -Task Build

# Install to modules directory
$modulePath = "$HOME\Documents\PowerShell\Modules"
Copy-Item -Recurse -Force .\Build\SecretManagement.Sops $modulePath\
```

### PowerShell Gallery

**Planned** - Publication to PowerShell Gallery is under consideration for a future release.

### Upgrading

To upgrade to a newer version:

```powershell
# Unregister all vaults using this module first
Get-SecretVault | Where-Object { $_.ModuleName -eq 'SecretManagement.Sops' } | ForEach-Object {
    Unregister-SecretVault -Name $_.Name
}

# Remove old module version
Remove-Module SecretManagement.Sops -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse "$HOME\Documents\PowerShell\Modules\SecretManagement.Sops" -Force

# Install new version (follow "From GitHub Releases" instructions above)

# Re-register your vaults
Register-SecretVault -Name 'GitOpsSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\infrastructure\secrets'
    Recurse = $true
}
```

### Uninstalling

To completely remove SecretManagement.Sops:

```powershell
# 1. Unregister all vaults
Get-SecretVault | Where-Object { $_.ModuleName -eq 'SecretManagement.Sops' } | ForEach-Object {
    Unregister-SecretVault -Name $_.Name
}

# 2. Remove the module
Remove-Module SecretManagement.Sops -Force -ErrorAction SilentlyContinue

# 3. Delete module files (PowerShell 7+)
Remove-Item -Recurse "$HOME\Documents\PowerShell\Modules\SecretManagement.Sops" -Force

# Or for Windows PowerShell 5.1
Remove-Item -Recurse "$HOME\Documents\WindowsPowerShell\Modules\SecretManagement.Sops" -Force
```

### Set Up Encryption Keys

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

# Get YAML content (returns raw YAML string)
$yamlContent = Get-Secret -Name 'config/settings' -Vault 'GitOpsSecrets' -AsPlainText
# Parse with your preferred YAML parser (e.g., powershell-yaml module)
```


## Vault Parameters

Configure vault behavior with these parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Path` | String | **Required** | Directory containing SOPS-encrypted files |
| `FilePattern` | String | `*.yaml` | File pattern to match (e.g., `*.yml`) |
| `Recurse` | Boolean | `$false` | Search subdirectories recursively |
| `NamingStrategy` | String | `RelativePath` | How to name secrets: `RelativePath` or `FileName` |
| `AgeKeyFile` | String | `$null` | Path to age key file (overrides `SOPS_AGE_KEY_FILE` environment variable) |
| `RequireEncryption` | Boolean | `$false` | Only include SOPS-encrypted files; exclude plaintext files |

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

### Example: Custom Configuration

```powershell
Register-SecretVault -Name 'ProductionSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\infra\secrets\production'
    FilePattern = '*.yaml'
    Recurse = $true
    NamingStrategy = 'RelativePath'
    RequireEncryption = $true  # Only include SOPS-encrypted files
}
```

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

### Short Name Access

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

### YAML Secrets with Namespaces

YAML secrets work seamlessly with namespace support:

```powershell
# Get YAML content (returns raw YAML string)
$yamlContent = Get-Secret -Name 'apps/foo/bar/dv1/config' -Vault 'GitOpsSecrets' -AsPlainText

# Parse with powershell-yaml if you need structured data
# Install-Module -Name powershell-yaml
# $parsed = ConvertFrom-Yaml $yamlContent
```

## Filtering and Encryption Control

### RequireEncryption Parameter

The `RequireEncryption` vault parameter provides security by ensuring only SOPS-encrypted files are accessible through the vault. This is especially useful when storing both encrypted secrets and plaintext configuration files in the same directory structure.

**How it works:**
- Excludes files without SOPS metadata
- Respects `.sops.yaml` configuration (excludes files matching `unencrypted_suffix` patterns)
- Provides an additional security layer to prevent accidental exposure of plaintext files

**Example: Onboarding a Vault with Encryption Filtering**

```powershell
# Scenario: You have a mixed directory with both encrypted secrets and plaintext configs
# Directory structure:
#   C:\repos\config\
#     ├── database.yaml (SOPS-encrypted)
#     ├── api-keys.yaml (SOPS-encrypted)
#     ├── readme.txt (plaintext)
#     └── template.yaml (plaintext, matches unencrypted_suffix in .sops.yaml)

# Register vault with encryption filtering enabled
Register-SecretVault -Name 'SecureSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\config'
    FilePattern = '*.yaml'
    Recurse = $true
    RequireEncryption = $true  # Only include SOPS-encrypted files
}

# List secrets - only encrypted files appear
Get-SecretInfo -Vault 'SecureSecrets'
# Returns: database, api-keys
# Excludes: readme.txt (doesn't match *.yaml), template.yaml (plaintext)
```

**Use cases:**
- **Production vaults**: Ensure only encrypted secrets are accessible
- **Mixed repositories**: Work with repos containing both secrets and configuration templates
- **Security compliance**: Prevent accidental retrieval of unencrypted files

### Wildcard Filtering

Filter secrets by name pattern using the `-Filter` parameter:

```powershell
# List all secrets in a specific namespace
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter 'database/*'

# List secrets matching a pattern
Get-SecretInfo -Vault 'GitOpsSecrets' -Filter 'prod-*'

# Combine with RequireEncryption for secure, filtered access
Register-SecretVault -Name 'FilteredVault' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\secrets'
    RequireEncryption = $true
}
Get-SecretInfo -Vault 'FilteredVault' -Filter 'apps/*/prod/*'
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

# Set using path syntax to target specific YAML field
Set-Secret -Name 'database/config' -Vault 'GitOpsSecrets' -Secret '.password: "NewPassword123!"'

# Multi-line YAML for complex structures
$yamlContent = @'
stringData:
  license-key: ABC-123-DEF-456
  config.json: '{"setting": "value"}'
'@
Set-Secret -Name 'app/config' -Vault 'GitOpsSecrets' -Secret $yamlContent

# Set a hashtable (converts to YAML structure)
$secretData = @{
    'license-key' = 'ABC-123-DEF-456'
    'config' = @{ setting = 'value' }
}
Set-Secret -Name 'app/settings' -Vault 'GitOpsSecrets' -Secret $secretData
```

**How it works:**

**For existing files:**
- Uses a patch-first approach with `sops --set` to preserve file structure and comments
- String secrets support three input modes:
  1. **Path syntax**: `.stringData.password: newValue` - Updates specific nested field
  2. **Multi-line YAML**: Entire YAML structure - Patches multiple fields
  3. **Plain string**: Simple value - Wraps in `{value: ...}` structure

**For new secrets:**
- Creates plaintext YAML at temporary `.insecure.yaml` path
- Encrypts in-place with SOPS from vault root (respects `.sops.yaml` path_regex)
- Deletes temporary unencrypted file

**Supported secret types:**
- `String` (plain text, path syntax, or YAML content)
- `SecureString` (converted to plaintext)
- `PSCredential` (converted to `{username: ..., password: ...}`)
- `Hashtable` (converted to YAML structure)
- `Byte[]` (converted to base64)

### Remove-Secret (Delete)

Use `Remove-Secret` to delete secrets:

```powershell
# Delete a secret (removes the entire YAML file)
Remove-Secret -Name 'api/old-key' -Vault 'GitOpsSecrets'

# Delete a namespaced secret
Remove-Secret -Name 'apps/foo/config' -Vault 'GitOpsSecrets'
```

**Important Notes:**
- `Remove-Secret` **always deletes the entire YAML file** - it does not support removing individual keys
- To remove specific keys from structured YAML, use `Set-Secret` with path syntax:
  ```powershell
  # Remove a specific field from a YAML file
  Set-Secret -Name 'config' -Vault 'GitOpsSecrets' -Secret '.stringData.old-key: null'
  ```

## FAQ

### Which encryption backend should I use?

- **age**: Best for getting started, simple local development, and GitOps workflows. No cloud dependencies required.
- **Azure Key Vault**: Best for Azure-based infrastructure and enterprise compliance requirements.
- **AWS KMS**: Best for AWS-based infrastructure and tight integration with AWS services.
- **GCP KMS**: Best for Google Cloud infrastructure.
- **PGP/GPG**: Legacy option, use age for new projects unless you have specific GPG requirements.

### When should I use RequireEncryption?

Use `RequireEncryption = $true` when:
- You have mixed directories with both encrypted secrets and plaintext config files
- You want to ensure only SOPS-encrypted files are accessible through the vault
- You're onboarding a production environment and need an extra security layer
- You want to prevent accidental exposure of plaintext files

### How do I migrate from another secret management solution?

```powershell
# 1. Export secrets from your current vault to SOPS format
Get-SecretInfo -Vault 'OldVault' | ForEach-Object {
    $secret = Get-Secret -Name $_.Name -Vault 'OldVault' -AsPlainText
    Set-Secret -Name $_.Name -Vault 'SopsVault' -Secret $secret
}

# 2. Verify all secrets migrated correctly
Get-SecretInfo -Vault 'SopsVault' | Measure-Object | Select-Object -ExpandProperty Count

# 3. Test retrieval
Get-Secret -Name 'test-secret' -Vault 'SopsVault' -AsPlainText
```

### Why does Get-Secret return YAML instead of parsed objects?

SecretManagement.Sops returns raw YAML strings to give you full control over parsing. This approach:
- Avoids dependency bloat (no required YAML parser)
- Lets you choose your preferred YAML library
- Provides maximum flexibility for complex YAML structures

To parse YAML, install `powershell-yaml`:
```powershell
Install-Module -Name powershell-yaml
$yamlContent = Get-Secret -Name 'config' -Vault 'SopsVault' -AsPlainText
$parsed = ConvertFrom-Yaml $yamlContent
```

### Can I use this with Kubernetes?

Yes! SecretManagement.Sops has built-in support for Kubernetes Secret manifests:

```powershell
# Create a Kubernetes Secret
$secret = New-KubernetesSecret -Name 'my-secret' -Namespace 'default' -Data @{
    username = 'admin'
    password = 'secretPassword123'
}

# Save and encrypt with SOPS
$secret | Out-File -Encoding utf8 k8s-secret.yaml
sops -e -i k8s-secret.yaml

# Later, retrieve specific keys
$password = Get-Secret -Name 'my-secret/password' -Vault 'K8sSecrets' -AsPlainText
```

### How do I handle secret rotation?

```powershell
# Update a secret
Set-Secret -Name 'database/password' -Vault 'SopsVault' -Secret 'NewPassword123!'

# The SOPS file is updated in-place, preserving structure and comments
# Commit and push the encrypted file to your Git repository
git add secrets/database.yaml
git commit -m "Rotate database password"
git push
```

### What's the difference between RelativePath and FileName naming strategies?

- **RelativePath** (default): Uses the full folder path as the secret name
  - `secrets/apps/prod/database.yaml` → `apps/prod/database`
  - Best for organized hierarchies with namespaces

- **FileName**: Uses only the filename without the path
  - `secrets/apps/prod/database.yaml` → `database`
  - Best for flat structures or when you manage organization outside the vault

### Can I use this in CI/CD pipelines?

Absolutely! Here's an example for GitHub Actions:

```yaml
- name: Decrypt secrets with SOPS
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
  run: |
    # Register vault
    pwsh -Command "
      Register-SecretVault -Name 'PipelineSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
        Path = './secrets'
        Recurse = \$true
      }

      # Use secrets
      \$apiKey = Get-Secret -Name 'api-key' -Vault 'PipelineSecrets' -AsPlainText
      Write-Host '::add-mask::' + \$apiKey
    "
```

### Do I need to refresh the vault after pulling new secrets from git?

No. SecretManagement.Sops is stateless by design—every call to `Get-SecretInfo` or `Get-Secret` performs a fresh filesystem scan. When team members add new secrets to the repository:

```powershell
# Before git pull
Get-SecretInfo -Vault 'GitOpsSecrets' | Measure-Object  # 10 secrets

# Pull changes with new secrets
git pull

# Immediately see new secrets - no refresh needed
Get-SecretInfo -Vault 'GitOpsSecrets' | Measure-Object  # 12 secrets
```

This design prioritizes correctness for GitOps workflows. There's no need to unregister/re-register the vault or call any refresh command.

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

- **YAML Only**: Currently supports YAML files only
- **Stateless Design**: Every operation rescans the filesystem (ensures GitOps correctness; may impact performance for very large vaults)
- **No Unlock-SecretVault**: Credential pre-caching not implemented
- **String Return Type**: Get-Secret returns raw YAML strings; users must parse with their preferred YAML parser
- **File-Level Deletion**: Remove-Secret deletes entire files; use Set-Secret with path syntax to remove individual keys

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

### Example 5: Parse YAML Secrets

```powershell
# Get-Secret returns raw YAML strings - parse with powershell-yaml for structured access
Install-Module -Name powershell-yaml -Scope CurrentUser

# Get and parse a complex YAML secret
$yamlContent = Get-Secret -Name 'app/config' -Vault 'GitOpsSecrets' -AsPlainText
$config = ConvertFrom-Yaml $yamlContent

# Access structured data
$dbPassword = $config.database.password
$apiKeys = $config.stringData.Keys
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

**Version**: 0.4.4 | [Releases](https://github.com/coryb-xyz/SecretManagement.Sops/releases) | [Issues](https://github.com/coryb-xyz/SecretManagement.Sops/issues)
