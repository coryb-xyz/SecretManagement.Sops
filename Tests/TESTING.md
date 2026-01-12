# Testing Guidelines for SecretManagement.Sops

## Error Assertion Standard

When testing error conditions, use the following standard pattern for consistency and clarity:

### ✅ Standard Pattern (RECOMMENDED)

```powershell
# Use Should -Throw with -ErrorAction Stop and specific message pattern
{
    Set-Secret -Name 'test' -Secret 'value' -VaultName 'NonExistent' -ErrorAction Stop
} | Should -Throw -ExpectedMessage '*Vault*not found*'
```

**Why this pattern:**
- `-ErrorAction Stop` ensures non-terminating errors become catchable
- `-ExpectedMessage` validates specific error message content
- Scriptblock syntax `{ }` is required for Should -Throw
- Produces clear error output when assertion fails

### Alternative Patterns

For tests where the function already throws terminating errors, `-ErrorAction Stop` can be omitted:

```powershell
# When function throws terminating errors by default
{ Invoke-SopsDecrypt -FilePath 'nonexistent.yaml' } | Should -Throw
```

However, **prefer including the expected message** for better test clarity:

```powershell
# Better - validates the specific error
{ Invoke-SopsDecrypt -FilePath 'nonexistent.yaml' } | Should -Throw '*not found*'
```

## YAML Content Validation

When validating decrypted YAML content, use structured validation instead of regex matching:

### ✅ Use Test-YamlContent Helper

```powershell
$decrypted = Get-Secret -Name 'test' -Vault 'MyVault' -AsPlainText
Test-YamlContent -YamlContent $decrypted -ExpectedValues @{
    'stringData.api-key' = 'expected-value'
    'metadata.name' = 'my-secret'
} | Should -Be $true
```

### ❌ Avoid Brittle Regex Matching

```powershell
# DON'T DO THIS - fragile to whitespace/formatting changes
$decrypted | Should -Match 'api-key:\s*expected-value'
```

**Why Test-YamlContent is better:**
- Format-agnostic (whitespace, key order don't matter)
- Supports nested paths with dot notation
- Better error messages when values don't match
- Tests behavior, not formatting

## Test Environment Management

All test files should use the standard helper functions for environment management:

```powershell
BeforeAll {
    # Import test helpers
    $testHelpersPath = Join-Path $PSScriptRoot 'TestHelpers.psm1'
    Import-Module $testHelpersPath -Force

    # Save environment state (location, environment variables, registered vaults)
    $script:testState = Initialize-TestEnvironment

    # ... test-specific setup
}

AfterAll {
    # Restore environment state (location, environment variables, cleanup test vaults)
    Restore-TestEnvironment -State $script:testState
}
```

This ensures:
- Consistent test isolation
- Automatic cleanup of test vaults
- Environment variable restoration
- Working directory restoration
