# SecretManagement.Sops - Requirements Document

## Executive Summary

This document outlines the requirements for building a PowerShell SecretManagement extension vault that wraps Mozilla SOPS (Secrets OPerationS). The goal is to provide PowerShell developers with a native, ergonomic interface for managing SOPS-encrypted files while maintaining compatibility with existing SOPS tooling and GitOps workflows. The module is designed as a generic SOPS file manager - it works with any YAML files encrypted by SOPS, whether they are Kubernetes Secret manifests, application configs, or other structured data.

---

## Background and Motivation

### Current State

SOPS provides file-based secret encryption with support for multiple KMS backends (Azure Key Vault, AWS KMS, GCP KMS, PGP, age). In GitOps workflows, SOPS-encrypted files (commonly Kubernetes Secret manifests for FluxCD, but also application configs and other structured data) are committed to Git repositories and automatically decrypted at deployment time.

Current SOPS usage requires:
- Direct CLI invocation (`sops -d`, `sops -e`)
- Manual file manipulation and parsing
- Environment-specific workarounds (e.g., 32-bit Azure CLI on Windows)
- No integration with PowerShell's native secret management ecosystem

### Problem Statement

DevOps engineers working in PowerShell environments lack a unified interface for SOPS operations. This results in:
- Inconsistent scripting patterns across teams
- Repeated boilerplate code for decrypt/encrypt operations
- No integration with other SecretManagement vaults (Azure Key Vault, SecretStore)
- Difficult transition for developers familiar with PowerShell SecretManagement

### Goals

1. Provide a PowerShell-native interface to SOPS-encrypted files via SecretManagement
2. Maintain full compatibility with existing SOPS-encrypted files and tooling
3. Support Azure Key Vault + age hybrid encryption configurations
4. Work seamlessly with GitOps workflows (FluxCD, ArgoCD, etc.)
5. Deliver excellent developer ergonomics on Windows with PowerShell Core
6. Remain generic - no file format assumptions beyond what SOPS supports

---

## Functional Requirements

### FR-1: SecretManagement Extension Vault Implementation

The module must implement the five required SecretManagement functions:

| Function | Status | Description |
|----------|--------|-------------|
| `Get-Secret` | ✅ Implemented | Retrieve decrypted file content by name |
| `Get-SecretInfo` | ✅ Implemented | List available SOPS files with metadata |
| `Set-Secret` | ✅ Implemented | Create or update encrypted file (supports SOPS --set for updates) |
| `Remove-Secret` | ✅ Implemented | Delete entire SOPS file from vault |
| `Test-SecretVault` | ✅ Implemented | Validate vault configuration and SOPS availability |

**Note on Remove-Secret**: This function removes entire files. To remove individual keys from structured files (e.g., Kubernetes Secrets), use `Set-Secret` with path syntax:
```powershell
".stringData.keyname: null" | Set-Secret -Name secretname -Vault vaultname
```

Optional functions (not implemented):

| Function | Priority | Description |
|----------|----------|-------------|
| `Unlock-SecretVault` | Low | Pre-authenticate with Azure/age (cache credentials) |
| `Set-SecretInfo` | Low | Update secret metadata without changing value |
| `Unregister-SecretVault` | Low | Cleanup operations when vault is unregistered |

### FR-2: Vault Registration and Configuration

The vault must support registration with customizable parameters:

```powershell
Register-SecretVault -Name 'GitOpsSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    # Required
    Path = 'C:\repos\infrastructure\secrets'  # Directory containing SOPS files

    # Optional - File discovery
    FilePattern = '*.yaml'                     # Default: *.yaml (also supports *.yml, *.json)
    Recurse = $true                            # Search subdirectories (default: $false)

    # Optional - Secret naming
    NamingStrategy = 'RelativePath'            # RelativePath (default) | FileName

    # Optional - Age encryption (per-vault key file)
    AgeKeyFile = 'C:\keys\vault-key.txt'       # Override SOPS_AGE_KEY_FILE for this vault
}
```

**VaultParameters Details:**

- **Path** (Required): Root directory containing SOPS-encrypted files
- **FilePattern** (Optional): Glob pattern for file discovery. Default: `*.yaml`
- **Recurse** (Optional): Search subdirectories. Default: `$false`
- **NamingStrategy** (Optional): How to name secrets in the vault:
  - `RelativePath` (default): Use path relative to vault root (e.g., `apps/prod/db` for `apps/prod/db.yaml`)
  - `FileName`: Use just the filename without extension (e.g., `db` for `apps/prod/db.yaml`)
- **AgeKeyFile** (Optional): Path to age private key file for this vault (overrides `SOPS_AGE_KEY_FILE` environment variable)

### FR-3: Secret Name Resolution

The vault supports two naming strategies:

**Strategy 1: Relative Path (Default)**
```
Vault Path: C:\repos\infra\secrets
File: C:\repos\infra\secrets\apps\prod\database.yaml
Secret Name: apps/prod/database
```

**Strategy 2: File Name Only**
```
Vault Path: C:\repos\infra\secrets
File: C:\repos\infra\secrets\apps\prod\database.yaml
Secret Name: database
```

**Namespace Support:**
Both strategies support namespaces via path separators:
- Exact match: `Get-Secret -Name 'apps/prod/database'`
- Short name match: `Get-Secret -Name 'database'` (if unique)
- Collision detection: Throws helpful error if multiple files share the same short name

### FR-4: Secret Types and Data Handling

Get-Secret returns decrypted file contents as:

| Return Type | When | Example |
|-------------|------|---------|
| `String` | YAML/JSON file content | Full decrypted YAML document as string (use `-AsPlainText`) |
| `Hashtable` | Parsed YAML/JSON | Decrypted and parsed to PowerShell object (default for structured data) |
| `SecureString` | Simple value files | Single-value secrets returned as SecureString (default when not using `-AsPlainText`) |

Set-Secret accepts:

| Input Type | Behavior | Example |
|------------|----------|---------|
| `String` | Plain text | Stored in `value: <string>` structure or as path-based update |
| `SecureString` | Secure string | Converted to plaintext, encrypted by SOPS |
| `PSCredential` | Credential | Stored as `username`/`password` keys |
| `Hashtable` | Structured data | Stored as YAML structure |
| `Byte[]` | Binary data | Base64-encoded and stored |

**String Input Modes for Set-Secret:**
1. **Path syntax**: `".stringData.password: newValue"` - Updates specific nested field
2. **YAML content**: Multi-line YAML that gets parsed and merged
3. **Plain string**: Simple value stored in default structure

### FR-5: Encryption Backend Support

Must support these SOPS encryption backends (in priority order):

1. **Azure Key Vault** (Primary) - via `az` CLI or environment credentials
2. **age** (Fallback/Local) - via `SOPS_AGE_KEY_FILE` or `SOPS_AGE_RECIPIENTS`
3. **AWS KMS** (Optional) - via AWS credentials
4. **GCP KMS** (Optional) - via GCP credentials
5. **PGP/GPG** (Legacy) - via GPG agent

### FR-6: File Format Support

| Format | Read | Write | Notes |
|--------|------|-------|-------|
| YAML | ✅ Supported | ✅ Supported | Primary format |
| JSON | ✅ Supported | ✅ Supported | Common for app configs |
| dotenv (.env) | ⚠️ Partial | ❌ Not implemented | SOPS can decrypt, but not yet tested |
| INI | ❌ Not implemented | ❌ Not implemented | Legacy format |
| Binary | ❌ Not implemented | ❌ Not implemented | SOPS binary mode |

### FR-7: Kubernetes Secret Integration

**Philosophy**: Kubernetes Secret manifests are treated as generic YAML files. The module does not parse `kind: Secret` or extract individual data keys.

Example workflow:

```yaml
# File: k8s/prod/database-secret.yaml (SOPS-encrypted)
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: production
type: Opaque
stringData:
  username: admin
  password: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
```

```powershell
# Get full manifest (decrypted)
$manifest = Get-Secret -Name 'k8s/prod/database-secret' -Vault 'GitOpsSecrets' -AsPlainText
# Returns entire YAML as string

# Update a specific field using path syntax
".stringData.password: newPassword123" | Set-Secret -Name 'k8s/prod/database-secret' -Vault 'GitOpsSecrets'

# Remove a key using path syntax
".stringData.obsolete-key: null" | Set-Secret -Name 'k8s/prod/database-secret' -Vault 'GitOpsSecrets'
```

This approach maintains compatibility with FluxCD and other GitOps tools while keeping the module generic.

---

## Non-Functional Requirements

### NFR-1: Platform Compatibility

| Platform | Support Level | Notes |
|----------|--------------|-------|
| Windows + PowerShell 7.x | Required | Primary target |
| Windows + PowerShell 5.1 | Required | Enterprise compatibility |
| Linux + PowerShell 7.x | Required | CI/CD pipelines |
| macOS + PowerShell 7.x | Optional | Developer workstations |

### NFR-2: Performance

- **Cold start**: < 2 seconds for vault registration and first secret retrieval
- **Warm retrieval**: < 500ms for cached file decryption
- **Batch operations**: Support efficient bulk retrieval without repeated SOPS invocations
- **Caching**: Optional in-memory caching with configurable TTL

### NFR-3: Security

1. **No plaintext persistence**: Decrypted secrets must never be written to disk
2. **Memory handling**: Use SecureString where appropriate; clear sensitive data from memory
3. **Credential passthrough**: Support Azure managed identity, service principal, and CLI authentication
4. **Audit logging**: Optional verbose logging for compliance (without secret values)

### NFR-4: Error Handling

The module must provide clear, actionable error messages:

```powershell
# Example: Azure CLI not found
Get-Secret -Name 'my-secret' -Vault 'GitOpsSecrets'
# Error: SOPS failed to decrypt: Azure CLI ('az') not found in PATH.
# Resolution: Install Azure CLI or configure age encryption as fallback.
# See: https://github.com/yourorg/SecretManagement.Sops#troubleshooting

# Example: Key access denied
Get-Secret -Name 'my-secret' -Vault 'GitOpsSecrets'  
# Error: Azure Key Vault access denied for key 'sops' in vault 'mykeyvault'.
# Resolution: Ensure your identity has 'decrypt' permission on the key.
```

### NFR-5: Compatibility

- ✅ Works alongside existing SOPS CLI usage (no file format changes)
- ✅ Respects `.sops.yaml` configuration files
- ✅ Does not interfere with FluxCD/ArgoCD SOPS decryption at deployment time
- ✅ Supports files encrypted with multiple key groups (Azure KV + age)
- ✅ Follows SecretManagement conventions (Remove-Secret deletes entire files)
- ✅ Generic approach - no assumptions about file structure beyond YAML/JSON validity

---

## Technical Design Considerations

### TD-1: SOPS CLI Wrapper Architecture

```
SecretManagement.Sops
├── SecretManagement.Sops.psd1          # Module manifest
├── SecretManagement.Sops.psm1          # Optional: Helper functions
└── SecretManagement.Sops.Extension/
    ├── SecretManagement.Sops.Extension.psd1
    └── SecretManagement.Sops.Extension.psm1  # Required 5 functions
```

### TD-2: SOPS Invocation Strategy

**Option A: CLI Wrapper (Recommended for v1.0)**
- Shell out to `sops` binary for all operations
- Pros: Simple, maintains SOPS version independence, leverages existing auth
- Cons: Process overhead, depends on SOPS binary availability

```powershell
# Internal implementation pattern
function Invoke-Sops {
    param(
        [string]$Command,
        [string]$FilePath,
        [hashtable]$Options
    )
    
    $sopsArgs = @($Command)
    if ($Options.Extract) { $sopsArgs += '--extract', $Options.Extract }
    if ($Options.InputType) { $sopsArgs += '--input-type', $Options.InputType }
    $sopsArgs += $FilePath
    
    $result = & sops @sopsArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SOPS failed: $result"
    }
    return $result
}
```

**Option B: Go Library via P/Invoke (Future)**
- Direct integration with SOPS Go library
- Pros: Better performance, no binary dependency
- Cons: Complex build, version coupling

### TD-3: Secret Indexing and Discovery

The vault maintains a simple index of available secrets:

```powershell
# Index structure (internal)
@{
    'apps/prod/database' = @{
        FilePath = 'C:\repos\infra\secrets\apps\prod\database.yaml'
        Name = 'apps/prod/database'
        Namespace = 'apps/prod'        # Path-based namespace
        ShortName = 'database'         # For collision detection
    }
}
```

Index refresh: On-demand (built fresh on each `Get-SecretInfo` or secret operation)

### TD-4: Windows-Specific Considerations

Based on known issues with SOPS on Windows:

1. **Azure CLI PATH issues**: The 64-bit Azure CLI (v2.51.0+) has PATH recognition problems with SOPS. Mitigations:
   - Document 32-bit CLI workaround
   - Support `AZURE_AUTH_METHOD=clientcredentials` environment variables
   - Provide clear error messages with resolution steps

2. **PowerShell execution context**: SOPS inherits environment from PowerShell session. Ensure:
   - Azure CLI auth tokens are available
   - `SOPS_AGE_KEY_FILE` is set if using age
   - Working directory doesn't affect `.sops.yaml` discovery

### TD-5: Caching Strategy

**Not implemented in current version.** Each operation invokes SOPS directly. Future enhancement could add:
- In-memory caching with TTL
- File modification time tracking
- Cache invalidation on file changes

---

## User Scenarios and Workflows

### Scenario 1: DevOps Engineer Retrieving Secrets for Local Development

```powershell
# One-time setup
Register-SecretVault -Name 'InfraSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = 'C:\repos\infrastructure\secrets'
    Recurse = $true
}

# Daily usage - get full file content
$appConfig = Get-Secret -Name 'apps/myapp/config' -Vault 'InfraSecrets' -AsPlainText

# Use in scripts - parse YAML to get specific values
$configData = Get-Secret -Name 'apps/database/credentials' -Vault 'InfraSecrets'
$connectionString = $configData.connectionString
```

### Scenario 2: Creating New SOPS-Encrypted Secret

```powershell
# Create a new secret file with structured data
$k8sSecret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{
        name = 'api-credentials'
        namespace = 'production'
    }
    stringData = @{
        'api-key' = 'sk-12345-abcdef'
    }
}

Set-Secret -Name 'production/api-credentials' -Vault 'InfraSecrets' -Secret $k8sSecret

# This creates: secrets/production/api-credentials.yaml (SOPS-encrypted)
# File is automatically encrypted based on .sops.yaml rules
```

### Scenario 3: Batch Secret Retrieval for Environment Setup

```powershell
# Get all secrets matching a pattern
$dbSecrets = Get-SecretInfo -Vault 'InfraSecrets' | 
    Where-Object Name -like 'database/*' |
    ForEach-Object { Get-Secret -Name $_.Name -Vault 'InfraSecrets' -AsPlainText }

# Export to .env format for local development
Get-SecretInfo -Vault 'InfraSecrets' | 
    Where-Object { $_.Metadata.Environment -eq 'development' } |
    ForEach-Object {
        "$($_.Name.ToUpper().Replace('/', '_'))=$(Get-Secret -Name $_.Name -Vault 'InfraSecrets' -AsPlainText)"
    } | Set-Content .env.local
```

### Scenario 4: CI/CD Pipeline Secret Access

```powershell
# In Azure DevOps pipeline (Service Principal auth via environment)
$env:AZURE_CLIENT_ID = '$(ServicePrincipalId)'
$env:AZURE_CLIENT_SECRET = '$(ServicePrincipalSecret)'
$env:AZURE_TENANT_ID = '$(TenantId)'

Register-SecretVault -Name 'PipelineSecrets' -ModuleName 'SecretManagement.Sops' -VaultParameters @{
    Path = '$(Build.SourcesDirectory)/secrets'
}

# Access secrets for deployment validation
$expectedVersion = Get-Secret -Name 'deployment/expected-image-tag' -Vault 'PipelineSecrets' -AsPlainText
```

### Scenario 5: Rotating a Secret

```powershell
# Update a specific field in an existing secret using path syntax
".stringData.password: $(Read-Host -Prompt 'Enter new password')" |
    Set-Secret -Name 'k8s/database-secret' -Vault 'InfraSecrets'

# Or update the entire file
$newPassword = Read-Host -AsSecureString -Prompt 'Enter new password'
Set-Secret -Name 'simple-password' -Vault 'InfraSecrets' -Secret $newPassword

# Verify the change
Test-SecretVault -Name 'InfraSecrets'
```

---

## Integration Points

### GitOps Compatibility

The module does not interfere with GitOps tools (FluxCD, ArgoCD, etc.):
- ✅ Files remain standard SOPS-encrypted format
- ✅ `.sops.yaml` configuration is respected
- ✅ No proprietary metadata added to files
- ✅ Works alongside `sops` CLI without conflicts

### Azure DevOps Pipelines

Support common CI/CD authentication patterns:
- Service Principal via environment variables
- Managed Identity (when running on Azure)
- Azure CLI authentication (interactive scenarios)

### Existing SecretManagement Vaults

Interoperate with other registered vaults:
```powershell
# Copy secret from SOPS to Azure Key Vault
$secret = Get-Secret -Name 'api-key' -Vault 'GitOpsSops'
Set-Secret -Name 'api-key' -Vault 'AzureKeyVault' -Secret $secret

# Compare secrets across vaults
$sopsSecret = Get-Secret -Name 'db-password' -Vault 'GitOpsSops' -AsPlainText
$akvSecret = Get-Secret -Name 'db-password' -Vault 'AzureKeyVault' -AsPlainText
$sopsSecret -eq $akvSecret  # Drift detection
```

---

## Testing Requirements

### Unit Tests

- Secret name resolution (all naming strategies)
- SOPS output parsing (YAML, JSON, binary)
- Error handling for common failure modes
- Kubernetes Secret manifest parsing

### Integration Tests

- End-to-end encrypt/decrypt with age keys
- Azure Key Vault authentication (mocked and live)
- Multi-key group files (Azure KV + age)
- Large file handling
- Concurrent access patterns

### Platform Tests

- Windows PowerShell 5.1 compatibility
- PowerShell 7.x on Windows, Linux, macOS
- Azure DevOps hosted agent compatibility

---

## Documentation Requirements

1. **README.md**: Quick start, installation, basic usage
2. **CONFIGURATION.md**: All vault parameters with examples
3. **TROUBLESHOOTING.md**: Common errors and resolutions (especially Windows/Azure CLI issues)
4. **SECURITY.md**: Security model, credential handling, audit logging
5. **MIGRATION.md**: Moving from direct SOPS CLI to SecretManagement
6. **DEVELOPMENT.md**: Contributing guide, architecture overview

---

## Implementation Status

### Phase 1: Core Functionality (MVP) - ✅ COMPLETE

- ✅ Module scaffolding and SecretManagement integration
- ✅ `Get-Secret` implementation (YAML/JSON)
- ✅ `Get-SecretInfo` implementation with namespace metadata
- ✅ `Test-SecretVault` implementation
- ✅ Vault registration with Path, FilePattern, Recurse, NamingStrategy parameters
- ✅ Azure Key Vault + age authentication support
- ✅ Comprehensive test coverage (94 tests passing)

### Phase 2: Write Support - ✅ COMPLETE

- ✅ `Set-Secret` implementation with path syntax support
- ✅ `Remove-Secret` implementation (file deletion only)
- ✅ New file creation with proper SOPS encryption
- ✅ Update support via SOPS --set for existing files
- ✅ Path-based encryption rules support (.sops.yaml)
- ✅ Comprehensive error messages with troubleshooting hints

### Phase 3: Additional Features - 🚧 IN PROGRESS

- ✅ Multiple naming strategies (RelativePath, FileName)
- ✅ Namespace support with collision detection
- ✅ String input modes (path syntax, YAML patching, plain strings)
- ❌ Secret caching with TTL (not implemented)
- ❌ `Unlock-SecretVault` for credential caching (not implemented)
- ⚠️ JSON format support (SOPS supports it, not thoroughly tested)
- ❌ dotenv format support (not implemented)

### Phase 4: Future Enhancements - ⏸️ NOT STARTED

- [ ] File watcher for index refresh
- [ ] Bulk operations optimization
- [ ] Binary file support
- [ ] In-memory caching layer
- [ ] Cross-platform CI/CD integration testing

### Phase 5: Documentation and Release - 🚧 IN PROGRESS

- ✅ Comprehensive inline documentation
- ✅ 94 passing tests covering core scenarios
- 🚧 README.md (needs update)
- 🚧 CONFIGURATION.md (needs creation)
- 🚧 TROUBLESHOOTING.md (needs creation)
- [ ] PowerShell Gallery publication

---

## Design Decisions Made

1. **Generic vs K8s-Specific**: ✅ Decided to remain generic. Kubernetes Secret manifests are treated as regular YAML files. No special parsing of `kind: Secret` or extraction of data keys. This aligns with SecretManagement conventions and keeps the module simple.

2. **Remove-Secret behavior**: ✅ Decided to delete entire files only. To remove individual keys, users should use `Set-Secret` with path syntax (e.g., `".key: null"`). This follows SecretManagement best practices.

3. **Naming strategies**: ✅ Implemented `RelativePath` (default) and `FileName`. Removed `KubernetesMetadata` strategy as it conflicts with the generic approach.

4. **Caching**: ✅ Decided not to implement caching in v1. Each operation invokes SOPS directly for simplicity and correctness.

## Open Questions for Future Versions

1. **Multi-document YAML**: SOPS supports multi-document YAML files. Should these be exposed as multiple secrets or single files?

2. **Age key management**: Should the module provide helpers for age key generation and distribution, or defer to external tooling?

3. **Vault-to-vault sync**: Is there demand for built-in synchronization between SOPS vault and other SecretManagement vaults?

4. **Performance optimization**: Should we add optional caching? File watchers for index refresh?

---

## References

- [PowerShell SecretManagement](https://github.com/PowerShell/SecretManagement)
- [SOPS - Secrets OPerationS](https://github.com/getsops/sops)
- [FluxCD SOPS Integration](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Azure Key Vault SOPS Integration](https://learn.microsoft.com/en-us/azure/aks/gitops-sops)
- [SecretManagement Extension Vault Development](https://devblogs.microsoft.com/powershell/secrets-management-module-vault-extensions/)
