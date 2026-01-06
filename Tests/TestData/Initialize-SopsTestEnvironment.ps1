#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap a SOPS test environment for unit tests or manual testing.

.DESCRIPTION
    This script creates a complete SOPS test environment including:
    - Age encryption key generation
    - Directory structure (minimal or GitOps-style)
    - Sample secrets (plain or inline generated)
    - SOPS configuration
    - Secret encryption
    - Optional SecretManagement vault registration

    Two modes are supported:
    - UnitTest: Minimal setup for Pester tests (default)
    - Manual: Full GitOps structure with vault registration for hands-on testing

.PARAMETER Mode
    Test environment mode: 'UnitTest' (minimal, for Pester) or 'Manual' (full GitOps, for hands-on testing).
    Default: UnitTest

.PARAMETER TestKeyDir
    Directory where age test keys will be stored.
    Default (UnitTest): Current script directory
    Default (Manual): "$HOME\.sops-test"

.PARAMETER VaultPath
    Root directory for the test vault.
    Default (UnitTest): Current script directory
    Default (Manual): "$HOME\gitops-test"

.PARAMETER ModulePath
    Path to the SecretManagement.Sops module manifest.
    Only used in Manual mode for vault registration.
    Defaults to attempting to find it relative to this script.

.PARAMETER SkipEncryption
    If specified, creates the directory structure and secrets but does not encrypt them.

.PARAMETER SkipRegistration
    If specified, does not register the vault with SecretManagement.
    Only applicable in Manual mode.

.PARAMETER Force
    If specified, recreates age key even if one already exists.

.EXAMPLE
    .\Initialize-SopsTestEnvironment.ps1
    Creates a minimal unit test environment in the current directory.

.EXAMPLE
    .\Initialize-SopsTestEnvironment.ps1 -Mode Manual
    Creates a full GitOps test vault at default location and registers it.

.EXAMPLE
    .\Initialize-SopsTestEnvironment.ps1 -Mode Manual -VaultPath "C:\test\my-vault"
    Creates a full GitOps test vault at a custom location.

.EXAMPLE
    .\Initialize-SopsTestEnvironment.ps1 -Mode UnitTest -Force
    Recreates the unit test environment with a new age key.

.NOTES
    Requires SOPS and age to be installed and available in PATH.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('UnitTest', 'Manual')]
    [string]$Mode = 'UnitTest',

    [Parameter()]
    [string]$TestKeyDir,

    [Parameter()]
    [string]$VaultPath,

    [Parameter()]
    [string]$ModulePath,

    [Parameter()]
    [switch]$SkipEncryption,

    [Parameter()]
    [switch]$SkipRegistration,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Helper functions
<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Message
${3:Parameter description}

.EXAMPLE
${4:An example}

.NOTES
${5:General notes}
#>
<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Message
${3:Parameter description}

.EXAMPLE
${4:An example}

.NOTES
${5:General notes}
#>
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Message
${3:Parameter description}

.EXAMPLE
${4:An example}

.NOTES
${5:General notes}
#>
function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Message
${3:Parameter description}

.EXAMPLE
${4:An example}

.NOTES
${5:General notes}
#>
function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

# Set defaults based on mode
if (-not $TestKeyDir) {
    $TestKeyDir = if ($Mode -eq 'UnitTest') { $PSScriptRoot } else { "$HOME\.sops-test" }
}

if (-not $VaultPath) {
    $VaultPath = if ($Mode -eq 'UnitTest') { $PSScriptRoot } else { "$HOME\gitops-test" }
}

# Convert to absolute paths (handles relative paths like '.')
$TestKeyDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestKeyDir)
$VaultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($VaultPath)

# Display configuration
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  SOPS Test Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Mode:       $Mode" -ForegroundColor White
Write-Host "  Key Dir:    $TestKeyDir" -ForegroundColor White
Write-Host "  Vault Path: $VaultPath" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Check prerequisites
Write-Step "Step 1: Checking prerequisites"

try {
    $null = Get-Command 'sops' -ErrorAction Stop
    Write-Success "SOPS found"
}
catch {
    Write-Error "SOPS not found in PATH. Install from: https://github.com/getsops/sops/releases"
}

try {
    $null = Get-Command 'age-keygen' -ErrorAction Stop
    Write-Success "age found"
}
catch {
    Write-Error "age not found in PATH. Install from: https://github.com/FiloSottile/age/releases"
}

# Step 2: Generate Age Key
Write-Step "Step 2: Generating age key"

New-Item -Path $TestKeyDir -ItemType Directory -Force | Out-Null
$keyFile = Join-Path $TestKeyDir 'test-key.txt'

if (Test-Path $keyFile) {
    if ($Force) {
        Remove-Item $keyFile -Force
        Write-Info "Removed existing key (Force mode)"
        & age-keygen -o $keyFile 2>&1 | Out-Null
        $publicKey = (Get-Content $keyFile | Select-Object -Skip 1 -First 1) -replace '^# public key: ', ''
        Write-Success "Generated new age key: $publicKey"
    }
    else {
        Write-Info "Using existing key at: $keyFile"
        $publicKey = (Get-Content $keyFile | Select-Object -Skip 1 -First 1) -replace '^# public key: ', ''
        Write-Success "Existing age key: $publicKey"
    }
}
else {
    & age-keygen -o $keyFile 2>&1 | Out-Null
    $publicKey = (Get-Content $keyFile | Select-Object -Skip 1 -First 1) -replace '^# public key: ', ''
    Write-Success "Generated age key: $publicKey"
}

Write-Info "Key file: $keyFile"

# Step 3: Create Directory Structure
Write-Step "Step 3: Creating directory structure"

if ($Mode -eq 'UnitTest') {
    # Minimal structure - just ensure VaultPath exists
    New-Item -Path $VaultPath -ItemType Directory -Force | Out-Null
    Write-Success "Directory structure ready at: $VaultPath"
}
else {
    # GitOps-style structure
    $dirs = @(
        "$VaultPath\apps\web\prod",
        "$VaultPath\apps\web\dev",
        "$VaultPath\apps\api",
        "$VaultPath\platform\monitoring",
        "$VaultPath\shared"
    )

    foreach ($dir in $dirs) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Write-Success "Created GitOps directory structure at: $VaultPath"
}

# Step 4: Create Sample Secrets
Write-Step "Step 4: Verifying test data files exist"

if ($Mode -eq 'UnitTest') {
    # In UnitTest mode, all plain YAML files should already be checked into git
    # We just verify they exist - no need to create them

    # Note: The *-plain.yaml files are the source of truth and are checked into git
    # The Initialize script only encrypts them to create the encrypted versions

    $expectedPlainFiles = @(
        'simple-secret-plain.yaml'
        'k8s-secret-plain.yaml'
        'credentials-plain.yaml'
        'api-key-plain.yaml'
        'database\postgres-plain.yaml'
        'apps\foo\bar\dv1\secret-plain.yaml'
        'a\b\c\d\e\f\deep-secret-plain.yaml'
        'env-prod\api_key-v2-plain.yaml'
        'k8s\myapp-plain.yaml'
        'config_unencrypted.yaml'
        'fake-sops.yaml'
    )

    $missingFiles = @()
    foreach ($file in $expectedPlainFiles) {
        $fullPath = Join-Path $VaultPath $file
        if (-not (Test-Path $fullPath)) {
            $missingFiles += $file
        }
        else {
            Write-Success "Verified: $file"
        }
    }

    if ($missingFiles.Count -gt 0) {
        throw "Missing required test data files (should be checked into git):`n  - $($missingFiles -join "`n  - ")"
    }
}
else {
    # Full GitOps secrets for manual testing
    $secrets = @{
        "apps\web\prod\database.yaml"      = @'
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
        "apps\web\dev\database.yaml"       = @'
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
        "apps\api\keys.yaml"               = @'
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
        "platform\monitoring\grafana.yaml" = @'
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
        "shared\tls-cert.yaml"             = @'
certificate: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKL0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ
  -----END CERTIFICATE-----
private-key: |
  -----BEGIN PRIVATE KEY-----
  MIIEvgIBADANBgkqhkiG9w0BAQABCDEFGHIJKLMNOPQRSTUVWXYZ123456789
  -----END PRIVATE KEY-----
'@
    }

    foreach ($secretPath in $secrets.Keys) {
        $fullPath = Join-Path $VaultPath $secretPath
        $secrets[$secretPath] | Set-Content $fullPath -NoNewline
        Write-Success "Created $secretPath"
    }
}

# Step 5: Create SOPS Configuration
Write-Step "Step 5: Creating SOPS configuration"

if ($Mode -eq 'UnitTest') {
    # Simple config for unit tests (includes unencrypted_suffix for EncryptionFiltering tests)
    $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    unencrypted_suffix: _unencrypted
    age: $publicKey
"@
}
else {
    # Config with encrypted_regex for K8s secrets
    $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    encrypted_regex: ^(data|stringData)$
    age: $publicKey
"@
}

$sopsConfigFile = Join-Path $VaultPath '.sops.yaml'
Set-Content -Path $sopsConfigFile -Value $sopsConfig -Encoding UTF8
Write-Success "Created .sops.yaml"

# Step 6: Encrypt Secrets
if (-not $SkipEncryption) {
    Write-Step "Step 6: Encrypting secrets"

    $env:SOPS_AGE_KEY_FILE = $keyFile

    if ($Mode -eq 'UnitTest') {
        Push-Location $VaultPath
        try {
            # Encrypt all *-plain.yaml files to their non-plain counterparts
            # Find all *-plain.yaml files recursively
            $plainFiles = Get-ChildItem -Path $VaultPath -Recurse -Filter "*-plain.yaml"

            if ($plainFiles.Count -eq 0) {
                throw "No *-plain.yaml files found. These should be checked into git."
            }

            foreach ($plainFile in $plainFiles) {
                $encryptedFile = $plainFile.FullName -replace '-plain\.yaml$', '.yaml'
                $relativePlainPath = $plainFile.FullName.Substring($VaultPath.Length + 1)
                $relativeEncryptedPath = $relativePlainPath -replace '-plain\.yaml$', '.yaml'

                $encrypted = & sops --encrypt $plainFile.FullName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "SOPS encryption failed for $relativePlainPath`: $encrypted"
                }

                Set-Content -Path $encryptedFile -Value $encrypted -Encoding UTF8
                Write-Success "Encrypted: $relativePlainPath -> $relativeEncryptedPath"
            }

            # Verify encryption works
            $testFile = 'simple-secret.yaml'
            if (Test-Path $testFile) {
                $decrypted = & sops --decrypt $testFile 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "SOPS decryption verification failed: $decrypted"
                }
                Write-Success "Verified encryption works"
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        # Encrypt all YAML files in place
        Push-Location $VaultPath
        try {
            $yamlFiles = Get-ChildItem -Path $VaultPath -Recurse -Filter "*.yaml" |
                Where-Object { $_.Name -ne ".sops.yaml" }

            foreach ($file in $yamlFiles) {
                $result = sops --encrypt --in-place $file.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Encrypted $($file.Name)"
                }
                else {
                    Write-Warning "Failed to encrypt $($file.Name): $result"
                }
            }
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-Info "Skipping encryption (SkipEncryption specified)"
}

# Step 7: Register Vault (Manual mode only)
if ($Mode -eq 'Manual' -and -not $SkipRegistration) {
    Write-Step "Step 7: Registering SecretManagement vault"

    # Determine module path
    if (-not $ModulePath) {
        # Try to find module relative to this script
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        # Navigate up from Tests/TestData to root, then to module
        $possiblePath = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "SecretManagement.Sops\SecretManagement.Sops.psd1"

        if (Test-Path $possiblePath) {
            $ModulePath = $possiblePath
        }
        else {
            Write-Error @"
Module manifest not found. Please specify -ModulePath parameter.
Tried: $possiblePath
"@
        }
    }

    if (-not (Test-Path $ModulePath)) {
        Write-Error "Module manifest not found at: $ModulePath"
    }

    Write-Info "Using module: $ModulePath"

    # Import the module
    Import-Module $ModulePath -Force

    # Unregister if exists (for clean slate)
    Unregister-SecretVault -Name 'GitOpsVault' -ErrorAction SilentlyContinue

    # Register the vault
    $vaultParams = @{
        Path           = $VaultPath
        FilePattern    = '*.yaml'
        Recurse        = $true
        NamingStrategy = 'RelativePath'
    }

    Register-SecretVault -Name 'GitOpsVault' -ModuleName $ModulePath -VaultParameters $vaultParams

    # Verify registration
    $vault = Get-SecretVault -Name 'GitOpsVault'
    Write-Success "Vault registered successfully!"
    Write-Info "Vault Name: $($vault.Name)"
    Write-Info "Module Name: $($vault.ModuleName)"
}
elseif ($Mode -eq 'Manual') {
    Write-Info "Skipping vault registration (SkipRegistration specified)"
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Mode:       $Mode" -ForegroundColor White
Write-Host "  Age Key:    $keyFile" -ForegroundColor White
Write-Host "  Vault Path: $VaultPath" -ForegroundColor White
Write-Host "  Public Key: $publicKey" -ForegroundColor White
Write-Host ""
Write-Host "Environment Variable (set this for SOPS operations):" -ForegroundColor Cyan
Write-Host "  `$env:SOPS_AGE_KEY_FILE = '$keyFile'" -ForegroundColor Yellow
Write-Host ""

if ($Mode -eq 'UnitTest') {
    Write-Host "Next Steps (Unit Testing):" -ForegroundColor Cyan
    Write-Host "  1. Set the SOPS_AGE_KEY_FILE environment variable (shown above)" -ForegroundColor White
    Write-Host "  2. Run tests: Invoke-Pester -Path ..\SecretManagement.Sops.Tests.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "IMPORTANT: Do NOT commit test-key.txt to version control!" -ForegroundColor Red
}
else {
    Write-Host "Next Steps (Manual Testing):" -ForegroundColor Cyan
    Write-Host "  1. Set the SOPS_AGE_KEY_FILE environment variable (shown above)" -ForegroundColor White
    Write-Host "  2. Test with: Get-SecretInfo -Vault GitOpsVault" -ForegroundColor White
    Write-Host "  3. Retrieve a secret: Get-Secret -Name 'apps/web/prod/database' -Vault GitOpsVault" -ForegroundColor White
    Write-Host ""
}
Write-Host ""
