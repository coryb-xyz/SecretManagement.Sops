# SecretManagement.Sops Dependencies

This document describes the dependency management system for the SecretManagement.Sops module.

## Overview

The module has both **required** and **optional** dependencies:

- **Required**: External tools that must be installed for the module to function
- **Optional**: PowerShell modules that enhance functionality but aren't strictly necessary

## Dependency Files

### 1. `requiredModules.psd1`

Central configuration file defining all dependencies:

- **OptionalModules**: PowerShell modules from PSGallery
  - `powershell-yaml` - YAML parser for Kubernetes Secrets and SOPS files

- **ExternalTools**: Binary tools that must be installed separately
  - `sops` (required) - Core encryption/decryption
  - `age` (optional) - Encryption backend alternative
  - `az` (optional) - Azure CLI for Azure Key Vault backend

- **DevelopmentModules**: Only needed for development
  - `Pester` - Testing framework
  - `PSScriptAnalyzer` - Code analysis
  - `platyPS` - Help documentation generator
  - `InvokeBuild` - Build automation tool

### 2. `Install-SopsVaultDependencies.ps1`

Bootstrap script for setting up the development environment.

**Usage:**

```powershell
# Interactive setup (prompts for each optional dependency)
.\Install-SopsVaultDependencies.ps1

# Include development tools
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment

# Non-interactive check (no installations)
.\Install-SopsVaultDependencies.ps1 -SkipOptional -NonInteractive

# Install for all users (requires admin)
.\Install-SopsVaultDependencies.ps1 -Scope AllUsers
```

**What it does:**

1. Checks for external tools (SOPS, age, Azure CLI)
2. Provides installation instructions for missing tools
3. Optionally installs PowerShell modules from PSGallery
4. Displays summary of all dependencies

### 3. `Install-ModuleDependency.ps1`

Helper function used internally by the module to auto-install dependencies.

**Location:** `SecretManagement.Sops\Private\Install-ModuleDependency.ps1`

**Features:**

- Checks if a module is available
- Prompts user to install from PSGallery if missing
- Supports both interactive and non-interactive modes
- Validates installation after completion

## YAML Parser Module

The module requires `powershell-yaml` for parsing Kubernetes Secret manifests and SOPS files. The module uses module-qualified cmdlet syntax (`powershell-yaml\ConvertFrom-Yaml`) to ensure deterministic behavior even when other YAML modules are loaded in the session.

## Installing External Tools

### SOPS (Required)

**Windows:**
```powershell
# WinGet (recommended)
winget install Mozilla.SOPS

# Chocolatey
choco install sops

# Scoop
scoop install sops
```

**Linux:**
```bash
# Download from releases
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

**macOS:**
```bash
brew install sops
```

### age (Optional)

**Windows:**
```powershell
winget install FiloSottile.age
# or
scoop install age
```

**Linux:**
```bash
apt install age
```

**macOS:**
```bash
brew install age
```

### Azure CLI (Optional)

**Windows:**
```powershell
winget install Microsoft.AzureCLI
```

**Linux:**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**macOS:**
```bash
brew install azure-cli
```

## Installing PowerShell Modules

### Automatic (Recommended)

The module will automatically offer to install YAML parsers when needed:

```powershell
# Just use the module - it will prompt if needed
Get-Secret -Name k8s/namespace/secret -Vault MySopsVault
```

### Manual Installation

```powershell
# Install powershell-yaml
Install-Module -Name powershell-yaml -MinimumVersion 0.4.0 -Scope CurrentUser
```

### Development Dependencies

```powershell
# For contributors/developers (recommended: use the automated installer)
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment

# Or install manually
Install-Module -Name InvokeBuild, Pester, PSScriptAnalyzer, platyPS -Scope CurrentUser
```

## Checking Dependencies

```powershell
# Quick check - only required tools
.\Install-SopsVaultDependencies.ps1 -SkipOptional -NonInteractive

# Full check with prompts
.\Install-SopsVaultDependencies.ps1

# Check everything including dev tools
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment
```

## Design Decisions

### Why Not in RequiredModules?

We intentionally **do not** include YAML parsers in the module manifest's `RequiredModules` because:

1. **Avoid installation bloat** - Users who only use simple secrets don't need YAML parsers
2. **Graceful degradation** - Built-in parser works for simple cases
3. **User choice** - Let users decide when to install based on their needs
4. **Better UX** - Prompt at the right time with context about why it's needed

### Why powershell-yaml?

- **Mature and stable**: Well-established module with wide community adoption
- **Full YAML support**: Handles complex Kubernetes Secret manifests with nested structures
- **Required dependency**: Declared in module manifest to ensure availability
- **Module-qualified calls**: Uses `powershell-yaml\ConvertFrom-Yaml` to avoid conflicts with other YAML modules

The module uses module-qualified cmdlet syntax to ensure deterministic behavior even when other YAML modules are present in the session.

## Troubleshooting

### "Module not found after installation"

Restart your PowerShell session to refresh the module cache.

### "SOPS command not found"

Ensure SOPS is in your PATH:

```powershell
# Windows
$env:PATH -split ';' | Select-String sops

# Check SOPS version
sops --version
```

### "YAML parsing failed"

If you're getting YAML parsing errors:

1. Verify powershell-yaml is installed: `Get-Module -ListAvailable powershell-yaml`
2. If missing, install it: `Install-Module powershell-yaml -MinimumVersion 0.4.0 -Scope CurrentUser`
3. Restart PowerShell and try again

## For Contributors

Before developing:

```powershell
# Run the full bootstrap
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment

# Verify everything is working with the build system
.\build.ps1 -Task Build
```

See [docs/Building.md](docs/Building.md) for detailed build documentation.

## Reference

- SOPS: https://github.com/mozilla/sops
- age: https://github.com/FiloSottile/age
- Azure CLI: https://learn.microsoft.com/cli/azure/
- Yayaml: https://www.powershellgallery.com/packages/Yayaml
- powershell-yaml: https://www.powershellgallery.com/packages/powershell-yaml
