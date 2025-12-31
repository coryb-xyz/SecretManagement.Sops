# Contributing to SecretManagement.Sops

Thank you for your interest in contributing to SecretManagement.Sops! This document provides guidelines for contributing to the project.

## Code of Conduct

This project follows a standard code of conduct. Please be respectful and constructive in all interactions.

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:
- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior
- Actual behavior
- Your environment (PowerShell version, OS, SOPS version)
- Any relevant error messages or logs

### Suggesting Features

Feature suggestions are welcome! Please:
- Check existing issues to avoid duplicates
- Clearly describe the feature and its use case
- Explain how it would benefit users
- Consider implementation complexity

### Submitting Pull Requests

1. **Fork the repository** and create a feature branch
2. **Make your changes** following the coding standards below
3. **Write tests** for new functionality
4. **Run tests** to ensure nothing breaks
5. **Update documentation** (README, inline help, etc.)
6. **Submit a pull request** with a clear description of changes

## Development Setup

### Prerequisites

Install required tools and modules:

```powershell
# Install PowerShell modules
Install-Module -Name Pester -MinimumVersion 5.0.0
Install-Module -Name PSScriptAnalyzer
Install-Module -Name Microsoft.PowerShell.SecretManagement

# Install SOPS
# Download from: https://github.com/getsops/sops/releases

# Install age (for testing)
# Download from: https://github.com/FiloSottile/age/releases
```

### Clone and Setup

```powershell
# Clone your fork
git clone https://github.com/your-username/SecretManagement.Sops.git
cd SecretManagement.Sops

# Install module dependencies (includes InvokeBuild, Pester, PSScriptAnalyzer)
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment -NonInteractive
```

### Building and Testing

Use the build system for all development tasks:

```powershell
# Full build (clean, update manifest, analyze, test, compile, validate)
.\build.ps1 -Task Build

# Quick iteration (update manifest + analyze only, no tests)
.\build.ps1 -Task Quick

# Run tests only
.\build.ps1 -Task Test

# Run tests without analysis
.\build.ps1 -Task TestOnly

# Run analysis only
.\build.ps1 -Task Analyze
```

See [docs/Building.md](docs/Building.md) for detailed build documentation.

### Manual Testing (Advanced)

If you need to run tests manually without the build system:

```powershell
# Run all tests directly
Invoke-Pester -Path ./Tests -Output Detailed

# Run specific test file
Invoke-Pester -Path ./Tests/SecretManagement.Sops.Tests.ps1 -Output Detailed
```

### Manual Linting (Advanced)

If you need to run PSScriptAnalyzer manually:

```powershell
# Analyze with auto-fix
Invoke-ScriptAnalyzer -Path SecretManagement.Sops -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Fix -ErrorAction SilentlyContinue

# Analyze specific file
Invoke-ScriptAnalyzer -Path ./SecretManagement.Sops/Public/Get-Secret.ps1 -Settings PSScriptAnalyzerSettings.psd1
```

## Coding Standards

### PowerShell Style Guide

- **Cmdlet naming**: Use approved PowerShell verbs (`Get-`, `Set-`, `Remove-`, etc.)
- **Parameter naming**: Use PascalCase for parameter names
- **Variable naming**: Use camelCase for local variables
- **Indentation**: 4 spaces (no tabs)
- **Line length**: Maximum 120 characters
- **Brace style**: Opening brace on same line for functions and control structures

### Function Structure

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredParameter,

        [Parameter(Mandatory = $false)]
        [string]$OptionalParameter = 'default'
    )

    # Function body
}
```

### Comment-Based Help

All public functions must include comment-based help:

```powershell
<#
.SYNOPSIS
    Brief description of the function

.DESCRIPTION
    Detailed description of what the function does

.PARAMETER ParameterName
    Description of the parameter

.OUTPUTS
    Description of output type

.EXAMPLE
    Verb-Noun -ParameterName 'value'

    Description of what this example demonstrates
#>
```

### Error Handling

- Use `Write-Error` for non-terminating errors
- Use `throw` for terminating errors
- Provide helpful error messages with context
- Include troubleshooting hints where appropriate

### Testing Requirements

- All new functions must have unit tests
- Test both success and failure paths
- Use descriptive test names
- Follow Pester 5 syntax
- Aim for high code coverage

Example test structure:

```powershell
Describe 'Verb-Noun' {
    Context 'When parameter is valid' {
        It 'Should return expected result' {
            # Arrange
            $param = 'value'

            # Act
            $result = Verb-Noun -Parameter $param

            # Assert
            $result | Should -Be 'expected'
        }
    }

    Context 'When parameter is invalid' {
        It 'Should throw an error' {
            { Verb-Noun -Parameter $null } | Should -Throw
        }
    }
}
```

## Documentation

### README Updates

When adding features, update:
- Feature list in Overview section
- Quick Start examples (if applicable)
- Vault Parameters table (if adding parameters)
- Troubleshooting section (if adding common issues)

### Inline Documentation

- Update comment-based help for modified functions
- Add examples demonstrating new functionality
- Update parameter descriptions if behavior changes

### CHANGELOG

Add entries to CHANGELOG.md under `[Unreleased]`:
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for removed features
- **Fixed** for bug fixes
- **Security** for security-related changes

## Git Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation only
- `refactor/description` - Code refactoring

### Commit Messages

Write clear, descriptive commit messages:

```
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
- Bullet points are fine
- Use present tense ("Add feature" not "Added feature")
- Reference issues: Fixes #123, Relates to #456
```

### Pull Request Process

1. Update documentation and tests
2. Run the full build to ensure everything passes:
   ```powershell
   .\build.ps1 -Task Build
   ```
3. Fix any PSScriptAnalyzer issues or failing tests
4. Update CHANGELOG.md
5. Create PR with clear description of changes
6. Link related issues
7. Respond to review feedback

**Note**: The CI/CD pipeline will automatically run `.\build.ps1 -Task Build` on your PR.

## Questions?

If you have questions about contributing:
- Check existing documentation
- Review closed issues for similar questions
- Open a new issue with the `question` label

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Thank You!

Your contributions help make SecretManagement.Sops better for everyone!
