# Quick Start Guide - Running Tests

Quick reference for running SecretManagement.Sops tests.

## Prerequisites

```powershell
# Install required modules
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
Install-Module -Name Microsoft.PowerShell.SecretManagement -Force

# Install SOPS (if not already installed)
# Download from: https://github.com/getsops/sops/releases
# Verify: sops --version

# Setup test data
cd Tests\TestData
.\Setup-TestData.ps1
cd ..\..
```

## Quick Test Commands

```powershell
# All tests
Invoke-Pester -Path .\Tests

# Only read support tests (Phase 1)
Invoke-Pester -Path .\Tests -TagFilter 'ReadSupport'

# Only write support tests (Phase 3)
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport'

# Only unit tests (fast, no SOPS)
Invoke-Pester -Path .\Tests -TagFilter 'Unit'

# Integration tests only
Invoke-Pester -Path .\Tests -TagFilter 'Integration'

# Exclude specific tags
Invoke-Pester -Path .\Tests -TagFilter 'Integration' -ExcludeTag 'Kubernetes'
```

## Test Development Workflow

### TDD Workflow (Test-Driven Development)

```powershell
# 1. Run quick unit tests after each change
Invoke-Pester -Path .\Tests -TagFilter 'Unit'

# 2. Run specific test file while developing
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1

# 3. Run full suite before commit
Invoke-Pester -Path .\Tests
```

### Debugging Specific Tests

```powershell
# Run specific Describe block
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -FullNameFilter '*Set-Secret*'

# Run specific Context
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -FullNameFilter '*Secret Type Support*'

# Run with verbose output
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -Output Diagnostic
```

## Common Test Scenarios

### Before Implementing Write Support

```powershell
# Verify current read-only tests pass
Invoke-Pester -Path .\Tests -TagFilter 'ReadSupport'

# Review write support test expectations (won't run, just shows structure)
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -DryRun
```

### While Developing Write Support

```powershell
# Run only Set-Secret tests
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -FullNameFilter '*Set-Secret*'

# Run only Remove-Secret tests
Invoke-Pester -Path .\Tests\WriteSupport.Tests.ps1 -FullNameFilter '*Remove-Secret*'

# Run only write unit tests
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport','Unit'
```

### Pre-Commit Validation

```powershell
# Fast unit tests
Invoke-Pester -Path .\Tests -TagFilter 'Unit'

# Ensure no regressions
Invoke-Pester -Path .\Tests -TagFilter 'ReadSupport'

# Validate new functionality
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport'

# Full test suite
Invoke-Pester -Path .\Tests
```

## CI/CD Pipeline Commands

### Fast CI (Pull Request Checks)

```powershell
# Unit tests only (fast)
Invoke-Pester -Path .\Tests -TagFilter 'Unit' -CI
```

### Full CI (Pre-Merge)

```powershell
# All tests
Invoke-Pester -Path .\Tests -CI
```

## Troubleshooting

### Tests Skipped - SOPS Not Available

```powershell
# Check SOPS installation
Get-Command sops

# If not found, install from:
# https://github.com/getsops/sops/releases

# Verify after installation
sops --version
```

### Tests Failing - Test Data Not Set Up

```powershell
# Run setup script
cd Tests\TestData
.\Setup-TestData.ps1

# Verify age key exists
Test-Path .\test-key.txt

# Verify environment variable
$env:SOPS_AGE_KEY_FILE
```

### Tests Failing - Decryption Errors

```powershell
# Ensure age key is configured
$env:SOPS_AGE_KEY_FILE = "$PWD\Tests\TestData\test-key.txt"

# Test SOPS manually
sops -d .\Tests\TestData\simple-secret.yaml

# Recreate test data if corrupted
cd Tests\TestData
Remove-Item *.yaml
.\Setup-TestData.ps1
```

### View Test Results

```powershell
# HTML report (requires ReportUnit or similar)
# Install: dotnet tool install --global ReportUnit
# reportunit .\Tests\TestResults.xml

# View in VS Code
code .\Tests\TestResults.xml

# Parse with PowerShell
[xml]$results = Get-Content .\Tests\TestResults.xml
$results.'test-results'
```

## Advanced Usage

### Custom Tag Combinations

```powershell
# Run integration tests except Kubernetes
Invoke-Pester -Path .\Tests -TagFilter 'Integration' -ExcludeTag 'Kubernetes'

# Run only error handling tests
Invoke-Pester -Path .\Tests -TagFilter 'ErrorHandling'

# Run only file operations tests
Invoke-Pester -Path .\Tests -TagFilter 'FileOperations'

# Multiple tags (AND logic)
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport','Integration'
```

### Watch Mode (Manual)

```powershell
# Run tests on file change (requires manual re-run)
while ($true) {
    Clear-Host
    Write-Host "Running tests... (Ctrl+C to stop)" -ForegroundColor Cyan
    Invoke-Pester -Path .\Tests -TagFilter 'Unit'
    Write-Host "`nWaiting for changes... (Press any key to re-run)" -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
```

### Parallel Test Execution

```powershell
# Run different test suites in parallel (PowerShell 7+)
$jobs = @(
    (Start-Job { Invoke-Pester -Path .\Tests -TagFilter 'ReadSupport' })
    (Start-Job { Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport' })
)

$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

## Performance Benchmarks

Expected execution times on typical hardware:

| Command | Tests | Duration | Use Case |
|---------|-------|----------|----------|
| `-TagFilter 'Unit'` | ~20 | 5-10s | Development (TDD) |
| `-TagFilter 'ReadSupport'` | ~30 | 30-60s | Read support validation |
| `-TagFilter 'WriteSupport'` | ~50 | 60-120s | Write support validation |
| All tests | ~85 | 2-4 min | Pre-commit checks |

## Help and Documentation

```powershell
# View test README
Get-Content .\Tests\README.md

# List all available tags
Get-Content .\Tests\*.Tests.ps1 | Select-String "-Tag" | Sort-Object -Unique

# Get Pester help
Get-Help Invoke-Pester -Full
```

## Examples

### Example 1: First-Time Setup

```powershell
# Clone and setup
git clone <repo-url>
cd SecretManagement.Sops

# Install dependencies
Install-Module Pester, Microsoft.PowerShell.SecretManagement -Force

# Setup test data
cd Tests\TestData
.\Setup-TestData.ps1
cd ..\..

# Run tests
Invoke-Pester -Path .\Tests
```

### Example 2: Daily Development

```powershell
# Start PowerShell in project root
cd C:\git\sops-vault

# Make changes to code...

# Quick validation
Invoke-Pester -Path .\Tests -TagFilter 'Unit'

# If working on write support
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport'

# Before commit
Invoke-Pester -Path .\Tests
```

### Example 3: PR Validation

```powershell
# Ensure clean state
git status

# Run full test suite
Invoke-Pester -Path .\Tests

# Check for regressions
Invoke-Pester -Path .\Tests -TagFilter 'ReadSupport'

# Validate new functionality
Invoke-Pester -Path .\Tests -TagFilter 'WriteSupport'
```

---

For more details, see [README.md](README.md) in the Tests directory.
