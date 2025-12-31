# SecretManagement.Sops Test Suite

This directory contains the comprehensive test suite for the SecretManagement.Sops module.

## Test Organization

Tests are organized using Pester 5 tags to allow selective test execution:

### Test Files

- **[SecretManagement.Sops.Tests.ps1](SecretManagement.Sops.Tests.ps1)** - Phase 1 read-only functionality tests
- **[WriteSupport.Tests.ps1](WriteSupport.Tests.ps1)** - Phase 3 write support tests (Set-Secret, Remove-Secret)

### Test Tags

Tests use the following tag strategy for selective execution:

#### Functional Tags

| Tag | Description | Files |
|-----|-------------|-------|
| `ReadSupport` | Read-only operations (Get-Secret, Get-SecretInfo) | SecretManagement.Sops.Tests.ps1 |
| `WriteSupport` | Write operations (Set-Secret, Remove-Secret) | WriteSupport.Tests.ps1 |

#### Scope Tags

| Tag | Description | Speed |
|-----|-------------|-------|
| `Unit` | Isolated unit tests with no external dependencies | Fast |
| `Integration` | Tests requiring SOPS binary and test data | Medium |
| `RequiresSops` | Tests that require SOPS binary in PATH | Medium |
| `Scenarios` | End-to-end scenario tests | Slow |

#### Feature Tags

| Tag | Description |
|-----|-------------|
| `Kubernetes` | Kubernetes Secret-specific tests |
| `SecretTypes` | Tests for different secret types (String, SecureString, PSCredential, etc.) |
| `FileOperations` | File creation, management, and cleanup tests |
| `ErrorHandling` | Error handling and edge case tests |

## Running Tests

### Prerequisites

1. **Required Modules**:
   ```powershell
   Install-Module -Name Pester -MinimumVersion 5.0.0
   Install-Module -Name Microsoft.PowerShell.SecretManagement
   ```

2. **SOPS Binary**:
   - Download from: https://github.com/getsops/sops/releases
   - Ensure `sops` is in your PATH
   - Verify: `sops --version`

3. **Encryption Keys**:
   ```powershell
   # Set up age key for testing
   cd Tests/TestData
   .\Setup-TestData.ps1
   ```

### Run All Tests

```powershell
# Run all tests (both read and write support)
Invoke-Pester -Path .\Tests
```

### Run Tests by Functional Area

```powershell
# Run only read support tests (Phase 1)
Invoke-Pester -Path .\Tests -Tag 'ReadSupport'

# Run only write support tests (Phase 3)
Invoke-Pester -Path .\Tests -Tag 'WriteSupport'
```

### Run Tests by Scope

```powershell
# Run only fast unit tests (no SOPS required)
Invoke-Pester -Path .\Tests -Tag 'Unit'

# Run integration tests (requires SOPS)
Invoke-Pester -Path .\Tests -Tag 'Integration'

# Exclude slow scenario tests
Invoke-Pester -Path .\Tests -ExcludeTag 'Scenarios'
```

### Run Tests by Feature

```powershell
# Run only Kubernetes-related tests
Invoke-Pester -Path .\Tests -Tag 'Kubernetes'

# Run only error handling tests
Invoke-Pester -Path .\Tests -Tag 'ErrorHandling'

# Run secret type tests
Invoke-Pester -Path .\Tests -Tag 'SecretTypes'
```

### Combined Tag Queries

```powershell
# Run write support unit tests only
Invoke-Pester -Path .\Tests -Tag 'WriteSupport', 'Unit'

# Run all integration tests except write support
Invoke-Pester -Path .\Tests -Tag 'Integration' -ExcludeTag 'WriteSupport'

# Run read support tests that don't require SOPS
Invoke-Pester -Path .\Tests -Tag 'ReadSupport', 'Unit'
```

### CI/CD Pipeline Examples

```powershell
# Fast CI pipeline (unit tests only, ~10-30 seconds)
Invoke-Pester -Path .\Tests -Tag 'Unit' -Output Detailed

# Full CI pipeline (all tests, ~2-5 minutes)
Invoke-Pester -Path .\Tests -Output Detailed

# Pre-release validation (integration + scenarios)
Invoke-Pester -Path .\Tests -Tag 'Integration', 'Scenarios' -Output Detailed
```

### Generate Code Coverage

```powershell
# Generate code coverage for read support
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests'
$config.Filter.Tag = 'ReadSupport'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\SecretManagement.Sops\*.ps1'
Invoke-Pester -Configuration $config

# Generate code coverage for write support
$config = New-PesterConfiguration
$config.Run.Path = '.\Tests\WriteSupport.Tests.ps1'
$config.Filter.Tag = 'WriteSupport'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\SecretManagement.Sops\SecretManagement.Sops.Extension\*.ps1'
Invoke-Pester -Configuration $config
```

## Test Data Setup

The test suite requires SOPS-encrypted test data:

```powershell
cd Tests\TestData
.\Setup-TestData.ps1
```

This creates:
- `test-key.txt` - age encryption key for testing
- `simple-secret.yaml` - Simple SOPS-encrypted secret
- `k8s-secret.yaml` - Kubernetes Secret manifest
- `admin-credentials.yaml` - PSCredential test data
- `.sops.yaml` - SOPS configuration file

## Write Support Test Coverage (Phase 3)

The [WriteSupport.Tests.ps1](WriteSupport.Tests.ps1) file includes comprehensive tests for:

### Set-Secret Tests

- **Parameter Validation**: Required parameters, vault validation
- **Secret Types**: String, SecureString, PSCredential, Hashtable, byte[]
- **File Operations**:
  - New file creation
  - SOPS encryption verification
  - Directory creation
  - SOPS round-trip validation
- **Updates**:
  - Overwriting existing secrets
  - Changing secret types
  - Encryption preservation
  - No duplicate files
- **Error Handling**:
  - Invalid vault parameters
  - SOPS encryption failures
  - Special characters in names
  - Empty string secrets
- **Kubernetes Support**:
  - K8s Secret manifest creation
  - Individual data key extraction

### Remove-Secret Tests

- **Parameter Validation**: Required parameters, vault validation
- **Basic Operations**:
  - Successful removal
  - File deletion
  - SecretInfo cleanup
  - Return value validation
- **Error Handling**:
  - Non-existent secrets
  - Double removal
  - Special characters
- **Kubernetes Support**:
  - Individual data key removal
  - Entire secret removal
  - Multi-key handling
- **File Management**:
  - No impact on other secrets
  - Directory cleanup (future)

### Integration Scenarios

- Round-trip operations (Set → Get → Update → Get → Remove)
- Multiple concurrent secrets
- SOPS encryption preservation across updates
- Rapid create/update/delete operations

## Test Development Best Practices

When adding new tests:

1. **Use Appropriate Tags**: Tag tests with functional, scope, and feature tags
2. **Test Isolation**: Use `BeforeEach`/`AfterEach` for clean state
3. **TestDrive**: Use Pester's `TestDrive` for file operations
4. **Skip Conditions**: Use `-Skip:(-not $script:SopsAvailable)` for SOPS-dependent tests
5. **Descriptive Names**: Use clear test names that describe expected behavior
6. **Cleanup**: Always clean up test resources in `AfterEach`/`AfterAll`
7. **Error Testing**: Test both success and failure paths

### Example Test Structure

```powershell
Describe 'MyFeature' -Tag 'WriteSupport', 'Integration', 'MyFeatureTag' {
    BeforeAll {
        # One-time setup (vault registration, etc.)
    }

    AfterAll {
        # One-time cleanup
    }

    Context 'Specific Scenario' -Tag 'SubFeature' {
        BeforeEach {
            # Per-test setup (unique test names, etc.)
            $script:TestName = "test-$(New-Guid)"
        }

        AfterEach {
            # Per-test cleanup (remove secrets, etc.)
            if ($script:TestName) {
                Remove-Secret -Name $script:TestName -Vault $vaultName -ErrorAction SilentlyContinue
            }
        }

        It 'Does something specific' -Skip:(-not $script:SopsAvailable) {
            # Test implementation
        }
    }
}
```

## Troubleshooting Test Failures

### SOPS Not Available

If you see "SOPS not available" warnings:

1. Install SOPS: https://github.com/getsops/sops/releases
2. Add to PATH
3. Verify: `sops --version`

### Test Data Not Set Up

If tests fail with "test data not available":

```powershell
cd Tests\TestData
.\Setup-TestData.ps1
```

### Age Key Not Configured

If SOPS decryption fails:

```powershell
$env:SOPS_AGE_KEY_FILE = "$(Get-Location)\Tests\TestData\test-key.txt"
```

### Permission Errors

On Linux/macOS, ensure key file permissions:

```bash
chmod 600 Tests/TestData/test-key.txt
```

## Performance Benchmarks

Expected test execution times on typical hardware:

| Test Category | Count | Duration | Notes |
|---------------|-------|----------|-------|
| Unit Tests (ReadSupport) | ~20 | 5-10s | No SOPS required |
| Unit Tests (WriteSupport) | ~15 | 5-10s | No SOPS required |
| Integration Tests (Read) | ~10 | 30-60s | Requires SOPS |
| Integration Tests (Write) | ~35 | 60-120s | Requires SOPS + file I/O |
| Scenarios | ~5 | 30-60s | End-to-end tests |
| **Total** | **~85** | **2-4 min** | Full test suite |

## CI/CD Integration

### Azure DevOps Pipeline

```yaml
steps:
  - task: PowerShell@2
    displayName: 'Install Dependencies'
    inputs:
      targetType: inline
      script: |
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
        Install-Module -Name Microsoft.PowerShell.SecretManagement -Force

  - task: PowerShell@2
    displayName: 'Setup SOPS'
    inputs:
      targetType: inline
      script: |
        # Download and install SOPS
        # Configure age key from pipeline secrets

  - task: PowerShell@2
    displayName: 'Run Unit Tests'
    inputs:
      targetType: inline
      script: |
        Invoke-Pester -Path ./Tests -Tag 'Unit' -Output Detailed

  - task: PowerShell@2
    displayName: 'Run Integration Tests'
    inputs:
      targetType: inline
      script: |
        Invoke-Pester -Path ./Tests -Tag 'Integration' -Output Detailed
```

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install SOPS
        run: |
          wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
          sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
          sudo chmod +x /usr/local/bin/sops

      - name: Run Tests
        shell: pwsh
        run: |
          Install-Module -Name Pester, Microsoft.PowerShell.SecretManagement -Force
          cd Tests/TestData
          ./Setup-TestData.ps1
          cd ../..
          Invoke-Pester -Path ./Tests -Output Detailed
```

## Contributing

When contributing tests:

1. Follow the existing tag taxonomy
2. Ensure tests are isolated and can run in any order
3. Add appropriate skip conditions for missing dependencies
4. Update this README if adding new test categories or tags
5. Ensure all tests pass locally before submitting PR

## References

- [Pester Documentation](https://pester.dev/)
- [Pester Tags](https://pester.dev/docs/usage/tags)
- [Pester TestDrive](https://pester.dev/docs/usage/testdrive)
- [SecretManagement Testing Guidelines](https://github.com/PowerShell/SecretManagement/blob/main/Docs/ARCHITECTURE.md)
