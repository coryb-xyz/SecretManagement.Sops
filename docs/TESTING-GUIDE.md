# Testing Guide: GitOps-Style SOPS Vault with Namespace Support

This guide walks you through setting up a realistic GitOps-style secrets repository with SOPS encryption and testing the namespace support and write capabilities hands-on.

**Time to complete**: ~15-20 minutes
**Difficulty**: Beginner-friendly

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Quick Setup](#quick-setup)
3. [Testing Scenarios](#testing-scenarios)
4. [Cleanup](#cleanup)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, verify you have the required tools installed:

### 1. Check SOPS Installation

```powershell
sops --version
```

**Expected output**: `sops 3.x.x` (any 3.x version)

If not installed, install via:
- **Windows**: `winget install SecretsOPerationS.SOPS` or `choco install sops`
- **macOS**: `brew install sops`
- **Linux**: Download from [GitHub releases](https://github.com/mozilla/sops/releases)

### 2. Check age Installation

```powershell
age --version
```

**Expected output**: `v1.x.x` or similar

If not installed, install via:
- **Windows**: `winget install FiloSottile.age` or `choco install age`
- **macOS**: `brew install age`
- **Linux**: `apt install age` or download from [GitHub](https://github.com/FiloSottile/age)

### 3. Check PowerShell Module

First, navigate to your repository directory, then import the module:

```powershell
# Navigate to the repository (adjust path as needed)
cd C:\git\sops-vault

# Import the module
Import-Module .\SecretManagement.Sops\SecretManagement.Sops.psd1 -Force

# Verify it loaded
Get-Module SecretManagement.Sops
```

**Expected output**: Module should be loaded with version info showing `SecretManagement.Sops`

**Note**: Keep this PowerShell session open for the rest of the guide, or remember to re-import the module if you open a new session.

---

## Quick Setup

You have two options for setting up your test environment:

### Option 1: Automated Setup (Recommended)

Use the [Initialize-SopsTestEnvironment.ps1](../Tests/TestData/Initialize-SopsTestEnvironment.ps1) script to automatically create the entire test environment:

```powershell
# Run with default settings (creates vault in $HOME\gitops-test)
.\Tests\TestData\Initialize-SopsTestEnvironment.ps1 -Mode Manual

# Or customize the location
.\Tests\TestData\Initialize-SopsTestEnvironment.ps1 -Mode Manual -VaultPath "C:\test\my-vault" -TestKeyDir "C:\keys"

# View all options
Get-Help .\Tests\TestData\Initialize-SopsTestEnvironment.ps1 -Detailed
```

The script will:
- Generate an age encryption key
- Create a GitOps-style directory structure
- Create 5 sample secrets
- Configure SOPS
- Encrypt all secrets
- Register the vault with SecretManagement

After running the script, skip to [Testing Scenarios](#testing-scenarios) below.

> **Note**: The same script supports `-Mode UnitTest` for Pester testing with a minimal setup. This ensures consistency between manual and automated testing environments.

### Option 2: Manual Setup (Step-by-Step)

If you prefer to understand each step or customize the setup, follow the manual instructions below.

#### Step 1: Generate Age Key for Testing

Create a dedicated age key for this test vault:

```powershell
# Create directory for test keys
$testKeyDir = "$HOME\.sops-test"
New-Item -Path $testKeyDir -ItemType Directory -Force

# Generate age key
age-keygen -o "$testKeyDir\test-key.txt"
```

**Expected output**:
```
Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Important**: Copy the public key from the output - you'll need it in the next step!

#### Step 2: Create Test Directory Structure

Create a simple GitOps-style directory structure:

```powershell
# Set base directory (change this to your preferred location)
$gitOpsDir = "$HOME\gitops-test"

# Create directory structure
$dirs = @(
    "$gitOpsDir\apps\web\prod",
    "$gitOpsDir\apps\web\dev",
    "$gitOpsDir\apps\api",
    "$gitOpsDir\platform\monitoring",
    "$gitOpsDir\shared"
)

foreach ($dir in $dirs) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
}

Write-Host "✓ Created directory structure at: $gitOpsDir" -ForegroundColor Green
```

#### Step 3: Create Sample Secrets

Create 5 sample secret files (copy-paste each block):

##### 3.1 Production Database Secret

```powershell
$secret1 = @'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-prod
  namespace: web-app
type: Opaque
stringData:
  host: postgres.prod.example.com
  username: prod_user
  password: ProductionPass123!
'@

$secret1 | Set-Content "$gitOpsDir\apps\web\prod\database.yaml" -NoNewline
Write-Host "✓ Created apps/web/prod/database.yaml" -ForegroundColor Green
```

##### 3.2 Development Database Secret

```powershell
$secret2 = @'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-dev
  namespace: web-app
type: Opaque
stringData:
  host: postgres.dev.example.com
  username: dev_user
  password: DevPass123!
'@

$secret2 | Set-Content "$gitOpsDir\apps\web\dev\database.yaml" -NoNewline
Write-Host "✓ Created apps/web/dev/database.yaml" -ForegroundColor Green
```

##### 3.3 API Keys Secret

```powershell
$secret3 = @'
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
  namespace: api-service
type: Opaque
stringData:
  stripe-key: sk_test_ABC123
  sendgrid-key: SG.XYZ789
'@

$secret3 | Set-Content "$gitOpsDir\apps\api\keys.yaml" -NoNewline
Write-Host "✓ Created apps/api/keys.yaml" -ForegroundColor Green
```

##### 3.4 Grafana Admin Secret

```powershell
$secret4 = @'
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: monitoring
type: Opaque
stringData:
  admin-user: admin
  admin-password: GrafanaAdmin123!
'@

$secret4 | Set-Content "$gitOpsDir\platform\monitoring\grafana.yaml" -NoNewline
Write-Host "✓ Created platform/monitoring/grafana.yaml" -ForegroundColor Green
```

##### 3.5 TLS Certificate (Simple YAML)

```powershell
$secret5 = @'
certificate: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKL0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ
  -----END CERTIFICATE-----
private-key: |
  -----BEGIN PRIVATE KEY-----
  MIIEvgIBADANBgkqhkiG9w0BAQABCDEFGHIJKLMNOPQRSTUVWXYZ123456789
  -----END PRIVATE KEY-----
'@

$secret5 | Set-Content "$gitOpsDir\shared\tls-cert.yaml" -NoNewline
Write-Host "✓ Created shared/tls-cert.yaml" -ForegroundColor Green
```

#### Step 4: Create SOPS Configuration

Create `.sops.yaml` with your age public key:

```powershell
# Read the public key from the generated key file
$testKeyFile = "$testKeyDir\test-key.txt"
$publicKey = (Get-Content $testKeyFile | Select-String "public key:").ToString().Split(":")[1].Trim()

# Create .sops.yaml configuration with encrypted_regex for K8s secrets
$sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $publicKey
"@

$sopsConfig | Set-Content "$gitOpsDir\.sops.yaml"
Write-Host "✓ Created .sops.yaml with age key: $publicKey" -ForegroundColor Green
```

#### Step 5: Encrypt All Secrets with SOPS

Set the age key environment variable and encrypt all secrets:

```powershell
# Set environment variable for SOPS to find the key
$env:SOPS_AGE_KEY_FILE = "$testKeyDir\test-key.txt"

# Find and encrypt all YAML files (except .sops.yaml)
Push-Location $gitOpsDir
try {
    $yamlFiles = Get-ChildItem -Path $gitOpsDir -Recurse -Filter "*.yaml" |
                 Where-Object { $_.Name -ne ".sops.yaml" }

    foreach ($file in $yamlFiles) {
        $result = sops --encrypt --in-place $file.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Encrypted $($file.Name)" -ForegroundColor Green
        } else {
            Write-Warning "Failed to encrypt $($file.Name): $result"
        }
    }
} finally {
    Pop-Location
}

Write-Host "`n✓ All secrets encrypted!" -ForegroundColor Green
```

#### Step 6: Register the Vault

Register the directory as a SecretManagement vault:

```powershell
# Get the full path to the module manifest
# IMPORTANT: Change this to match YOUR repository location
$moduleManifest = "C:\git\sops-vault\SecretManagement.Sops\SecretManagement.Sops.psd1"

# Verify the module file exists
if (-not (Test-Path $moduleManifest)) {
    Write-Error "Module manifest not found at: $moduleManifest"
    Write-Host "Please update the path to match your repository location" -ForegroundColor Yellow
    return
}

# Import the module first
Import-Module $moduleManifest -Force

# Unregister if exists (for clean slate)
Unregister-SecretVault -Name 'GitOpsVault' -ErrorAction SilentlyContinue

# Register the vault with namespace support
Register-SecretVault -Name 'GitOpsVault' -ModuleName $moduleManifest -VaultParameters @{
    Path = $gitOpsDir
    FilePattern = '*.yaml'
    Recurse = $true
    NamingStrategy = 'RelativePath'
}

# Verify registration
Get-SecretVault -Name 'GitOpsVault'

Write-Host "`n✓ Vault registered successfully!" -ForegroundColor Green
Write-Host "`nYou're all set! Proceed to Testing Scenarios below." -ForegroundColor Cyan
```

---

## Testing Scenarios

Now that everything is set up, let's test the namespace support features!

### Scenario 1: Basic Secret Retrieval

#### 1.1 Get a Secret by Full Path

```powershell
# Get the production database secret
$secret = Get-Secret -Vault GitOpsVault -Name 'apps/web/prod/database' -AsPlainText

# Display the secret (it's a hashtable for K8s secrets)
$secret
```

**Expected output**:
```
Name                           Value
----                           -----
host                           postgres.prod.example.com
username                       prod_user
password                       ProductionPass123!
```

#### 1.2 Get API Keys as Hashtable

```powershell
$apiKeys = Get-Secret -Vault GitOpsVault -Name 'apps/api/keys' -AsPlainText
$apiKeys
```

**Expected output**:
```
Name                           Value
----                           -----
stripe-key                     sk_test_ABC123
sendgrid-key                   SG.XYZ789
```

**Note**: Because .sops.yaml is configured with `encrypted_regex: ^(data|stringData)$`, only the actual secret data is returned, not the Kubernetes metadata fields.

---

### Scenario 2: Namespace Collision Detection

The `database` secret exists in both `apps/web/prod/` and `apps/web/dev/`. Let's see what happens when we try to use just the short name:

#### 2.1 Try Ambiguous Short Name

```powershell
# This will fail because 'database' exists in multiple namespaces
try {
    Get-Secret -Vault GitOpsVault -Name 'database' -AsPlainText -ErrorAction Stop
} catch {
    Write-Host "Error (expected):" -ForegroundColor Yellow
    Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
}
```

**Expected output**:
```
Error (expected):
Multiple secrets with short name 'database' found:
  - apps/web/prod/database (C:\Users\...\gitops-test\apps\web\prod\database.yaml)
  - apps/web/dev/database (C:\Users\...\gitops-test\apps\web\dev\database.yaml)

Please specify the full path.
Example: Get-Secret -Name 'apps/web/prod/database'
```

#### 2.2 Resolve with Full Path

```powershell
# Use the full path to get the specific secret
$prodDb = Get-Secret -Vault GitOpsVault -Name 'apps/web/prod/database' -AsPlainText
$devDb = Get-Secret -Vault GitOpsVault -Name 'apps/web/dev/database' -AsPlainText

Write-Host "Prod DB Host: $($prodDb.host)" -ForegroundColor Green
Write-Host "Dev DB Host: $($devDb.host)" -ForegroundColor Cyan
```

**Expected output**:
```
Prod DB Host: postgres.prod.example.com
Dev DB Host: postgres.dev.example.com
```

---

### Scenario 3: Wildcard Listing

#### 3.1 List All Secrets in Web App Namespace

```powershell
$webSecrets = Get-SecretInfo -Vault GitOpsVault -Name 'apps/web/*'
$webSecrets | Format-Table Name, @{Label='Namespace';Expression={$_.Metadata.Namespace}}, @{Label='ShortName';Expression={$_.Metadata.ShortName}}
```

**Expected output**:
```
Name                    Namespace       ShortName
----                    ---------       ---------
apps/web/dev/database   apps/web/dev    database
apps/web/prod/database  apps/web/prod   database
```

#### 3.2 List All Platform Secrets

```powershell
$platformSecrets = Get-SecretInfo -Vault GitOpsVault -Name 'platform/*'
$platformSecrets | Format-Table Name, @{Label='Namespace';Expression={$_.Metadata.Namespace}}
```

**Expected output**:
```
Name                          Namespace
----                          ---------
platform/monitoring/grafana   platform/monitoring
```

#### 3.3 List All Secrets in the Vault

```powershell
$allSecrets = Get-SecretInfo -Vault GitOpsVault -Name '*'
Write-Host "Total secrets: $($allSecrets.Count)"
$allSecrets | Format-Table Name, Type, @{Label='IsK8s';Expression={$_.Metadata.IsKubernetesSecret}}
```

**Expected output**:
```
Total secrets: 5

Name                          Type      IsK8s
----                          ----      -----
apps/api/keys                 Hashtable True
apps/web/dev/database         Hashtable True
apps/web/prod/database        Hashtable True
platform/monitoring/grafana   Hashtable True
shared/tls-cert               Hashtable False
```

---

### Scenario 4: Inspect K8s Secret Metadata

```powershell
$grafanaInfo = Get-SecretInfo -Vault GitOpsVault -Name 'platform/monitoring/grafana'

Write-Host "`nGrafana Secret Metadata:" -ForegroundColor Cyan
Write-Host "  Full Name: $($grafanaInfo.Name)"
Write-Host "  Namespace: $($grafanaInfo.Metadata.Namespace)"
Write-Host "  Short Name: $($grafanaInfo.Metadata.ShortName)"
Write-Host "  Is K8s Secret: $($grafanaInfo.Metadata.IsKubernetesSecret)"
Write-Host "  K8s Metadata Name: $($grafanaInfo.Metadata.KubernetesName)"
Write-Host "  K8s Namespace: $($grafanaInfo.Metadata.KubernetesNamespace)"
```

**Expected output**:
```
Grafana Secret Metadata:
  Full Name: platform/monitoring/grafana
  Namespace: platform/monitoring
  Short Name: grafana
  Is K8s Secret: True
  K8s Metadata Name: grafana-admin
  K8s Namespace: monitoring
```

---

### Scenario 5: Write Support - Creating Secrets

Now let's test the write capabilities by creating new secrets in the vault.

#### 5.1 Create a Simple String Secret

```powershell
# Create a new API key secret
Set-Secret -Name 'apps/web/staging/api-key' -Secret 'staging-api-key-xyz789' -Vault GitOpsVault

# Verify it was created and encrypted
$stagingKey = Get-Secret -Name 'apps/web/staging/api-key' -Vault GitOpsVault -AsPlainText
$stagingKey
```

**Expected output**:
```
value: staging-api-key-xyz789
```

**Note**: The secret is stored as a SOPS-encrypted YAML file at `apps/web/staging/api-key.yaml`.

#### 5.2 Create a Hashtable Secret (Multiple Values)

```powershell
# Create a new database configuration
$dbConfig = @{
    host = 'redis.staging.example.com'
    port = 6379
    password = 'RedisStaging123!'
    ssl_enabled = $true
}

Set-Secret -Name 'apps/web/staging/redis' -Secret $dbConfig -Vault GitOpsVault

# Retrieve and verify
$redis = Get-Secret -Name 'apps/web/staging/redis' -Vault GitOpsVault -AsPlainText
$redis
```

**Expected output**:
```
host: redis.staging.example.com
port: 6379
password: RedisStaging123!
ssl_enabled: true
```

#### 5.3 Create a PSCredential Secret

```powershell
# Create credentials
$cred = [PSCredential]::new('service-account', (ConvertTo-SecureString 'ServicePass456!' -AsPlainText -Force))

Set-Secret -Name 'platform/monitoring/prometheus-creds' -Secret $cred -Vault GitOpsVault

# Retrieve and verify
$promCreds = Get-Secret -Name 'platform/monitoring/prometheus-creds' -Vault GitOpsVault -AsPlainText
$promCreds
```

**Expected output**:
```
username: service-account
password: ServicePass456!
```

---

### Scenario 6: Write Support - Updating Secrets

Let's update existing secrets to test the patch/update functionality.

#### 6.1 Update a Simple Secret

```powershell
# Update the staging API key we created earlier
Set-Secret -Name 'apps/web/staging/api-key' -Secret 'new-staging-key-abc123' -Vault GitOpsVault

# Verify the update
$updatedKey = Get-Secret -Name 'apps/web/staging/api-key' -Vault GitOpsVault -AsPlainText
$updatedKey
```

**Expected output**:
```
value: new-staging-key-abc123
```

**Note**: The old value is completely replaced. SOPS re-encrypts the file with the new value.

#### 6.2 Update a Production Database Password

```powershell
# Update the production database password
$newProdDb = @{
    host = 'postgres.prod.example.com'
    username = 'prod_user'
    password = 'NewSecurePassword2024!'
}

Set-Secret -Name 'apps/web/prod/database' -Secret $newProdDb -Vault GitOpsVault

# Verify the update
$updatedDb = Get-Secret -Name 'apps/web/prod/database' -Vault GitOpsVault -AsPlainText
$updatedDb
```

**Expected output**:
```
host: postgres.prod.example.com
username: prod_user
password: NewSecurePassword2024!
```

#### 6.3 Change Secret Type (String to Hashtable)

```powershell
# Convert the staging API key from a simple string to a structured secret
$apiConfig = @{
    'api-key' = 'new-staging-key-abc123'
    'api-secret' = 'secret-component-xyz'
    'endpoint' = 'https://api.staging.example.com'
}

Set-Secret -Name 'apps/web/staging/api-key' -Secret $apiConfig -Vault GitOpsVault

# Verify the structure changed
$structuredApi = Get-Secret -Name 'apps/web/staging/api-key' -Vault GitOpsVault -AsPlainText
$structuredApi
```

**Expected output**:
```
api-key: new-staging-key-abc123
api-secret: secret-component-xyz
endpoint: https://api.staging.example.com
```

---

### Scenario 7: Write Support - Deleting Secrets

Finally, let's test removing secrets from the vault.

#### 7.1 Remove a Single Secret

```powershell
# Remove the staging API key
Remove-Secret -Name 'apps/web/staging/api-key' -Vault GitOpsVault

# Verify it's gone
$removed = Get-Secret -Name 'apps/web/staging/api-key' -Vault GitOpsVault -ErrorAction SilentlyContinue
$removed | Should -BeNullOrEmpty

# Also verify the file is deleted
Test-Path "$gitOpsDir\apps\web\staging\api-key.yaml"
```

**Expected output**:
```
False
```

#### 7.2 Remove a Secret and Verify Others Are Unaffected

```powershell
# Remove the staging redis secret
Remove-Secret -Name 'apps/web/staging/redis' -Vault GitOpsVault

# Verify production secrets still exist
$prodDb = Get-Secret -Name 'apps/web/prod/database' -Vault GitOpsVault -AsPlainText
$prodDb | Should -Not -BeNullOrEmpty

Write-Host "✓ Staging redis removed, production database intact" -ForegroundColor Green
```

#### 7.3 Cleanup Test Secrets

```powershell
# Remove all the test secrets we created
Remove-Secret -Name 'platform/monitoring/prometheus-creds' -Vault GitOpsVault -ErrorAction SilentlyContinue

# List remaining secrets to verify
Get-SecretInfo -Vault GitOpsVault -Name '*' | Format-Table Name
```

---

### Scenario 8: Round-Trip Testing

Verify that the complete create → read → update → delete cycle works seamlessly.

```powershell
$testSecretName = 'shared/roundtrip-test'

# 1. Create
Write-Host "`n==> Step 1: Creating secret" -ForegroundColor Cyan
Set-Secret -Name $testSecretName -Secret 'initial-value' -Vault GitOpsVault
$value1 = Get-Secret -Name $testSecretName -Vault GitOpsVault -AsPlainText
Write-Host "Created: $value1" -ForegroundColor Green

# 2. Update
Write-Host "`n==> Step 2: Updating secret" -ForegroundColor Cyan
Set-Secret -Name $testSecretName -Secret 'updated-value' -Vault GitOpsVault
$value2 = Get-Secret -Name $testSecretName -Vault GitOpsVault -AsPlainText
Write-Host "Updated: $value2" -ForegroundColor Green

# 3. Update to different type
Write-Host "`n==> Step 3: Changing to hashtable" -ForegroundColor Cyan
Set-Secret -Name $testSecretName -Secret @{key1='value1'; key2='value2'} -Vault GitOpsVault
$value3 = Get-Secret -Name $testSecretName -Vault GitOpsVault -AsPlainText
Write-Host "Changed to hashtable:" -ForegroundColor Green
$value3

# 4. Delete
Write-Host "`n==> Step 4: Removing secret" -ForegroundColor Cyan
Remove-Secret -Name $testSecretName -Vault GitOpsVault
$value4 = Get-Secret -Name $testSecretName -Vault GitOpsVault -ErrorAction SilentlyContinue
if (-not $value4) {
    Write-Host "✓ Secret successfully removed" -ForegroundColor Green
}

Write-Host "`n✓ Round-trip test completed successfully!" -ForegroundColor Green
```

**Expected output**:
```
==> Step 1: Creating secret
Created: value: initial-value

==> Step 2: Updating secret
Updated: value: updated-value

==> Step 3: Changing to hashtable
Changed to hashtable:
key1: value1
key2: value2

==> Step 4: Removing secret
✓ Secret successfully removed

✓ Round-trip test completed successfully!
```

---

## Cleanup

When you're done testing, clean up the test environment:

```powershell
# Unregister the vault
Unregister-SecretVault -Name 'GitOpsVault'

# Remove test directory
Remove-Item -Path $gitOpsDir -Recurse -Force

# Optionally remove test age key
# Remove-Item -Path $testKeyDir -Recurse -Force

Write-Host "✓ Cleanup complete!" -ForegroundColor Green
```

---

## Troubleshooting

### Issue: "SOPS not found" or "age not found"

**Solution**: Ensure SOPS and age are in your PATH. Restart PowerShell after installation.

```powershell
# Verify PATH
$env:PATH -split ';' | Select-String "sops"
$env:PATH -split ';' | Select-String "age"
```

### Issue: "Failed to decrypt" errors

**Solution**: Ensure the `SOPS_AGE_KEY_FILE` environment variable is set:

```powershell
$env:SOPS_AGE_KEY_FILE = "$HOME\.sops-test\test-key.txt"
```

### Issue: "Yayaml parser failed" warnings

**Solution**: If you see warnings like "A parameter cannot be found that matches parameter name 'Yaml'", this has been fixed in the latest version. The module now auto-detects which YAML parser is installed and uses the correct parameters. To eliminate any warnings, ensure you have either Yayaml or powershell-yaml installed:

```powershell
# Install Yayaml (recommended - faster)
Install-Module Yayaml -Scope CurrentUser

# OR install powershell-yaml
Install-Module powershell-yaml -Scope CurrentUser
```

### Issue: "Multiple secrets found" error

**Solution**: This is expected behavior! Use the full path instead of the short name:

```powershell
# Instead of:
Get-Secret -Name 'database' -Vault GitOpsVault

# Use:
Get-Secret -Name 'apps/web/prod/database' -Vault GitOpsVault
```

### Issue: Full Kubernetes manifest returned instead of just secret data

**Symptoms**: When retrieving a Kubernetes Secret, you see fields like `apiVersion`, `kind`, `metadata`, `type` in the output instead of just your secret data.

**Solution**: This issue has been fixed in the latest version. The module now correctly filters Kubernetes Secrets to return only the contents of `data` and `stringData` fields. Ensure:

1. Your `.sops.yaml` has `encrypted_regex` configured:
   ```yaml
   creation_rules:
     - path_regex: \.yaml$
       encrypted_regex: ^(data|stringData)$
       age: <your-public-key>
   ```

2. The module is correctly loaded with all dependencies:
   ```powershell
   Import-Module SecretManagement.Sops -Force

   # Verify the filtering function is available
   Get-Command Get-EncryptedSecretData -ErrorAction Stop
   ```

3. Check verbose output to see what's happening:
   ```powershell
   Get-Secret -Name 'my-secret' -Vault MyVault -Verbose
   ```

**Expected behavior**: For Kubernetes Secrets, you should only see the keys from `stringData` or `data`, not the Kubernetes manifest fields.

### Issue: Vault registration fails

**Solution**: Ensure the module is loaded and the path exists:

```powershell
# Reload module
Import-Module .\SecretManagement.Sops\SecretManagement.Sops.psd1 -Force

# Verify path
Test-Path $gitOpsDir
```

---

## Next Steps

Now that you've tested the namespace support and write features, you can:

1. **Adapt for Your GitOps Repo**: Use this structure as a template for your actual secrets repository
2. **Add More Secrets**: Create additional namespaces and secrets to test complex scenarios
3. **Integrate with CI/CD**: Use these secrets in your deployment pipelines
4. **Automate Secret Rotation**: Use `Set-Secret` to programmatically update secrets on a schedule
5. **Multiple Vaults**: Register multiple GitOps repos as separate vaults

---

## Summary

You've successfully:
- ✅ Created a GitOps-style secrets repository
- ✅ Encrypted secrets with SOPS and age
- ✅ Registered a SecretManagement vault with namespace support
- ✅ Retrieved secrets by full path and short name
- ✅ Tested collision detection for ambiguous names
- ✅ Used wildcards to filter secrets by namespace
- ✅ Extracted individual data keys from Kubernetes secrets
- ✅ Inspected secret metadata including K8s information
- ✅ Created new secrets with `Set-Secret`
- ✅ Updated existing secrets (including type changes)
- ✅ Deleted secrets with `Remove-Secret`
- ✅ Performed complete round-trip create/read/update/delete operations

**Congratulations!** You now understand how to use the full feature set of the SOPS SecretManagement vault. 🎉

For more information, see:
- [README.md](README.md) - Full module documentation
- [Tests/NamespaceSupport.Tests.ps1](Tests/NamespaceSupport.Tests.ps1) - Comprehensive test examples
- [DEPENDENCIES.md](DEPENDENCIES.md) - Dependency management guide
