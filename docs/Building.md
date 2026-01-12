# Building SecretManagement.Sops

This document describes the build process for the SecretManagement.Sops module.

## Prerequisites

The build system automatically installs required dependencies, but you can manually install them:

```powershell
Install-Module -Name InvokeBuild -Scope CurrentUser
Install-Module -Name Pester -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
```

## Quick Start

```powershell
# Run the full build pipeline
.\build.ps1

# Run specific build tasks
.\build.ps1 -Task Quick          # Fast build without tests
.\build.ps1 -Task UpdateManifest # Auto-generate function exports only
.\build.ps1 -Task Test          # Run tests only
```

## Available Build Tasks

| Task | Description |
|------|-------------|
| `.` (default) | Full build pipeline: Clean → UpdateManifest → Analyze → Test |
| `Build` | Complete build with compilation and validation: UpdateManifest → Analyze → ValidateSource → Test → Compile → ValidateImport |
| `BuildWithDocs` | Complete build including help documentation: UpdateManifest → Analyze → ValidateSource → Test → GenerateHelp → Compile → ValidateImport |
| `Quick` | Fast iteration build (UpdateManifest → Analyze, skips tests and compilation) |
| `Compile` | Compile module into Build directory (combines all functions into single .psm1) |
| `GenerateHelp` | Generate external help files with platyPS (markdown + MAML) |
| `UpdateManifest` | Auto-generate FunctionsToExport from Public folder |
| `Analyze` | Run PSScriptAnalyzer for code quality checks |
| `Test` | Run Pester tests |
| `TestOnly` | Run tests without analysis |
| `ValidateImport` | Compile and verify built module can be imported successfully |
| `ValidateSource` | Verify source module can be imported |
| `Clean` | Clean build artifacts (removes Build directory) |

## Build Task Details

### Compile

This task compiles the module into a distributable package in the `Build/` directory:

- **Combines all function files** into two single `.psm1` files:
  - Main module: All Public and Private functions in one file
  - Extension module: All SecretManagement extension functions in one file
- **Preserves module structure**: Maintains the nested module architecture
- **Improves load performance**: Single file loads faster than 30+ individual files
- **Output location**: `Build/SecretManagement.Sops/`
- **Benefit**: Clean separation between source and distributable, ready for publishing

### UpdateManifest

This task automatically updates the module manifest with the correct list of exported functions:

- Scans all `.ps1` files in `SecretManagement.Sops/Public/`
- Updates `FunctionsToExport` in the `.psd1` manifest
- **Benefit**: No more manual maintenance of the function export list

### Analyze

Runs PSScriptAnalyzer with project-specific settings:

- Uses `PSScriptAnalyzerSettings.psd1` for configuration
- Enforces code quality and style consistency
- Fails the build if issues are found

### Test

Runs the full Pester test suite:

- Automatically installs module dependencies via `Install-SopsVaultDependencies.ps1`
- Runs all tests in the `Tests/` directory
- Generates `TestResults.xml` for CI/CD integration
- Fails the build if any tests fail

### ValidateImport

Ensures the compiled module can be imported:

- Compiles the module (if not already compiled)
- Imports the built module from `Build/SecretManagement.Sops/`
- Verifies exported commands are available
- Cleans up by removing the module

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/ci.yml`) automatically runs the build on:

- Push to `main` or `master` branches
- Pull requests targeting `main` or `master`
- Manual workflow dispatch

The CI pipeline:
1. Installs build dependencies (InvokeBuild, Pester, PSScriptAnalyzer)
2. Runs `.\build.ps1 -Task Build`
3. Uploads test results as artifacts

## Common Workflows

### Adding a New Public Function

1. Create your function file in `SecretManagement.Sops/Public/NewFunction.ps1`
2. Run `.\build.ps1 -Task UpdateManifest` to auto-add it to exports
3. The manifest will automatically include your new function

### Before Committing Changes

```powershell
# Run quick build to catch issues
.\build.ps1 -Task Quick

# Or run the full build
.\build.ps1
```

### Fixing Code Quality Issues

```powershell
# Run PSScriptAnalyzer with auto-fix
Invoke-ScriptAnalyzer -Path SecretManagement.Sops -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Fix -ErrorAction SilentlyContinue

# Verify fixes
.\build.ps1 -Task Analyze
```

### Understanding Analyzer Results

The Analyze task categorizes issues by severity:

- **Errors** (Red): Critical issues that fail the build - must be fixed
- **Warnings** (Yellow): Best practice violations - shown but don't fail the build
- **Information** (Gray): Suggestions - shown but don't fail the build

The build only fails on Error-severity issues.

### Local Development Iteration

When actively developing, use the `Quick` task for faster feedback:

```powershell
# Make changes to code
.\build.ps1 -Task Quick  # Fast: UpdateManifest + Analyze (no tests)

# When ready to verify everything
.\build.ps1              # Full: Clean + UpdateManifest + Analyze + Test
```

## Build Script Details

### Entry Point: `build.ps1`

The main build script that:
- Ensures InvokeBuild is installed
- Delegates to `SecretManagement.Sops.build.ps1`
- Provides a simple interface: `.\build.ps1 -Task TaskName`

### Build Definition: `SecretManagement.Sops.build.ps1`

Contains all build task definitions using InvokeBuild syntax:
- Task dependencies (e.g., `Build` depends on all other tasks)
- Task implementation using PowerShell scripts
- Error handling and validation

## Build Output Structure

The build process creates the following structure:

```
Build/
└── SecretManagement.Sops/
    ├── SecretManagement.Sops.psd1        # Module manifest (copied)
    ├── SecretManagement.Sops.psm1        # Compiled main module (7 private + 9 public functions)
    └── SecretManagement.Sops.Extension/
        ├── SecretManagement.Sops.Extension.psd1  # Extension manifest (copied)
        └── SecretManagement.Sops.Extension.psm1  # Compiled extension (10 private + 5 public functions)
```

**Source vs. Build:**
- **Source** (`SecretManagement.Sops/`): Development files with separate `.ps1` files
- **Build** (`Build/SecretManagement.Sops/`): Compiled distributable with combined `.psm1` files

**Usage:**
```powershell
# Import from source (development)
Import-Module ./SecretManagement.Sops/SecretManagement.Sops.psd1

# Import from build (production)
Import-Module ./Build/SecretManagement.Sops/SecretManagement.Sops.psd1
```

## Available Build Tasks

| Task | Description | Command |
|------|-------------|---------|
| `.` (default) | Full build pipeline: Clean → UpdateManifest → Analyze → Test | `.\build.ps1` |
| `Build` | Complete build with compilation and validation | `.\build.ps1 -Task Build` |
| `BuildWithDocs` | Complete build including help documentation | `.\build.ps1 -Task BuildWithDocs` |
| `Quick` | Fast iteration build (UpdateManifest → Analyze, skips tests) | `.\build.ps1 -Task Quick` |
| `Compile` | Compile module into Build directory | `.\build.ps1 -Task Compile` |
| `GenerateHelp` | Generate external help files with platyPS | `.\build.ps1 -Task GenerateHelp` |
| `UpdateManifest` | Auto-generate FunctionsToExport from Public folder | `.\build.ps1 -Task UpdateManifest` |
| `Analyze` | Run PSScriptAnalyzer for code quality checks | `.\build.ps1 -Task Analyze` |
| `Test` | Run Pester tests | `.\build.ps1 -Task Test` |
| `TestOnly` | Run tests without analysis | `.\build.ps1 -Task TestOnly` |
| `ValidateImport` | Compile and verify built module can be imported | `.\build.ps1 -Task ValidateImport` |
| `ValidateSource` | Verify source module can be imported | `.\build.ps1 -Task ValidateSource` |
| `Clean` | Clean build artifacts (removes Build directory) | `.\build.ps1 -Task Clean` |

## Help Documentation

The build system includes platyPS integration for generating external help files:

```powershell
# Generate help documentation
.\build.ps1 -Task GenerateHelp
```

This task:
- Generates markdown help files in `docs/cmdlet-help/` from comment-based help
- Creates MAML help file (`SecretManagement.Sops-help.xml`) in `SecretManagement.Sops/en-US/`
- Enables `Get-Help` support for all module cmdlets
- Automatically copied to Build output when compiling

Help files are included in GitHub Releases and allow users to run:
```powershell
Get-Help Get-Secret -Full
Get-Help Set-Secret -Examples
```

## Future Enhancements

Potential additions to the build process:

1. ✅ **Module Compilation**: ~~Combine all Public/Private `.ps1` files into a single `.psm1` for performance~~ **DONE!**
2. ✅ **Help Documentation**: ~~Generate external help files from comment-based help using platyPS~~ **DONE!**
3. ✅ **Packaging**: ~~Create publishable `.nupkg` for PowerShell Gallery~~ **Automated via GitHub Actions!**
4. **Versioning**: Auto-increment version numbers based on git tags
5. **Code Coverage**: Integrate Pester code coverage reporting
6. **Multi-platform Testing**: ~~Test on Windows, Linux, and macOS~~ **Partially done in CI (Windows + Linux)**
7. **Publishing**: Automated publishing to PowerShell Gallery

## Troubleshooting

### Build Fails with Module Import Errors

Ensure dependencies are installed:

```powershell
.\Install-SopsVaultDependencies.ps1 -NonInteractive
```

### PSScriptAnalyzer Errors

Run with auto-fix to correct common issues:

```powershell
Invoke-ScriptAnalyzer -Path SecretManagement.Sops -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Fix
```

### Test Failures

Run tests with detailed output:

```powershell
.\build.ps1 -Task TestOnly
```

Or run Pester directly for more control:

```powershell
Invoke-Pester -Path ./Tests -Output Detailed
```
