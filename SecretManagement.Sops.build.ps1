<#
.SYNOPSIS
    Build script for SecretManagement.Sops module using InvokeBuild

.DESCRIPTION
    This build script provides automated tasks for:
    - Cleaning build artifacts
    - Updating module manifests with auto-generated function exports
    - Running PSScriptAnalyzer
    - Running Pester tests
    - Building the module for distribution

.NOTES
    Requires InvokeBuild: Install-Module InvokeBuild -Scope CurrentUser
    Run with: Invoke-Build
#>

#Requires -Modules InvokeBuild

# Build configuration
$Script:ModuleName = 'SecretManagement.Sops'
$Script:SourcePath = Join-Path $PSScriptRoot $ModuleName
$Script:BuildPath = Join-Path $PSScriptRoot 'Build'
$Script:BuildModulePath = Join-Path $BuildPath $ModuleName
$Script:SourceManifestPath = Join-Path $SourcePath "$ModuleName.psd1"
$Script:TestsPath = Join-Path $PSScriptRoot 'Tests'

# Synopsis: Default task - runs full build pipeline
task . Clean, UpdateManifest, Analyze, Test

# Synopsis: Clean build artifacts
task Clean {
    Write-Build Green 'Cleaning build artifacts...'

    if (Test-Path $BuildPath) {
        Remove-Item $BuildPath -Recurse -Force
        Write-Build Gray "Removed Build directory"
    }
}

# Synopsis: Auto-generate FunctionsToExport in module manifest (only if changed)
task UpdateManifest {
    Write-Build Green 'Checking module manifest function exports...'

    # Get all public functions
    $publicPath = Join-Path $SourcePath 'Public'
    $publicFunctions = Get-ChildItem -Path "$publicPath/*.ps1" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty BaseName

    if (-not $publicFunctions) {
        throw "No public functions found in $publicPath"
    }

    Write-Build Gray "Found $($publicFunctions.Count) public functions: $($publicFunctions -join ', ')"

    # Get current FunctionsToExport from manifest
    $manifest = Import-PowerShellDataFile -Path $SourceManifestPath
    $currentFunctions = $manifest.FunctionsToExport

    # Compare current vs discovered functions
    $needsUpdate = $false
    if ($null -eq $currentFunctions) {
        $needsUpdate = $true
        Write-Build Yellow "Manifest has no FunctionsToExport defined"
    }
    elseif ($currentFunctions.Count -ne $publicFunctions.Count) {
        $needsUpdate = $true
        Write-Build Yellow "Function count mismatch: manifest has $($currentFunctions.Count), found $($publicFunctions.Count)"
    }
    else {
        $comparison = Compare-Object -ReferenceObject $publicFunctions -DifferenceObject $currentFunctions
        if ($comparison) {
            $needsUpdate = $true
            Write-Build Yellow "Function list has changed"
        }
    }

    # Only update if changed
    if ($needsUpdate) {
        Update-ModuleManifest -Path $SourceManifestPath -FunctionsToExport $publicFunctions
        Write-Build Green "Manifest updated with $($publicFunctions.Count) functions"
    }
    else {
        Write-Build Gray "Manifest already up to date with $($publicFunctions.Count) functions"
    }
}

# Synopsis: Run PSScriptAnalyzer
task Analyze {
    Write-Build Green 'Running PSScriptAnalyzer...'

    $analyzerParams = @{
        Path = $SourcePath
        Recurse = $true
        Settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
        ExcludeRule = @('PSAlignAssignmentStatement', 'PSUseConsistentIndentation')
        ErrorAction = 'SilentlyContinue'
    }

    # Run analyzer and filter out .psd1 manifest issues
    # Update-ModuleManifest generates these in a specific format that may not align with all rules
    $results = Invoke-ScriptAnalyzer @analyzerParams | Where-Object {
        -not ($_.ScriptPath -like '*.psd1' -and $_.RuleName -in @('PSAlignAssignmentStatement', 'PSAvoidTrailingWhitespace', 'PSUseConsistentIndentation'))
    }

    # Separate errors from warnings/info
    $errors = $results | Where-Object { $_.Severity -eq 'Error' }
    $warnings = $results | Where-Object { $_.Severity -eq 'Warning' }
    $info = $results | Where-Object { $_.Severity -eq 'Information' }

    # Display all results
    if ($results) {
        $results | Format-Table -AutoSize | Out-Host
    }

    # Report summary
    if ($warnings) {
        Write-Build Yellow "Found $($warnings.Count) warning(s)"
    }
    if ($info) {
        Write-Build Gray "Found $($info.Count) informational message(s)"
    }

    # Only fail on errors
    if ($errors) {
        throw "PSScriptAnalyzer found $($errors.Count) error(s)"
    }

    Write-Build Green 'PSScriptAnalyzer passed (no errors)'
}

# Synopsis: Compile module into Build directory
task Compile Clean, {
    Write-Build Green 'Compiling module...'

    # Create build directory structure
    $null = New-Item -ItemType Directory -Path $BuildModulePath -Force
    $extensionPath = Join-Path $BuildModulePath 'SecretManagement.Sops.Extension'
    $null = New-Item -ItemType Directory -Path $extensionPath -Force

    Write-Build Gray "Created build directory: $BuildModulePath"

    # Compile main module
    Write-Build Gray 'Compiling main module...'
    $mainModulePath = Join-Path $BuildModulePath "$ModuleName.psm1"
    $mainModuleContent = @"
# $ModuleName - Compiled Module
# This is a compiled version combining all Public and Private functions

"@

    # Add all Private functions
    $privatePath = Join-Path $SourcePath 'Private'
    $privateFiles = Get-ChildItem -Path "$privatePath/*.ps1" -ErrorAction SilentlyContinue
    foreach ($file in $privateFiles) {
        $mainModuleContent += "`n# region Private: $($file.BaseName)`n"
        $mainModuleContent += Get-Content $file.FullName -Raw
        $mainModuleContent += "`n# endregion`n"
    }

    # Add all Public functions
    $publicPath = Join-Path $SourcePath 'Public'
    $publicFiles = Get-ChildItem -Path "$publicPath/*.ps1" -ErrorAction SilentlyContinue
    foreach ($file in $publicFiles) {
        $mainModuleContent += "`n# region Public: $($file.BaseName)`n"
        $mainModuleContent += Get-Content $file.FullName -Raw
        $mainModuleContent += "`n# endregion`n"
    }

    # Add Export-ModuleMember
    $publicFunctionNames = $publicFiles.BaseName
    $mainModuleContent += "`n# Export public functions`n"
    $mainModuleContent += "Export-ModuleMember -Function @("
    $mainModuleContent += ($publicFunctionNames | ForEach-Object { "'$_'" }) -join ', '
    $mainModuleContent += ")`n"

    Set-Content -Path $mainModulePath -Value $mainModuleContent -Encoding UTF8
    Write-Build Gray "  Compiled main module with $($privateFiles.Count) private + $($publicFiles.Count) public functions"

    # Compile extension module
    Write-Build Gray 'Compiling extension module...'
    $extensionModulePath = Join-Path $extensionPath 'SecretManagement.Sops.Extension.psm1'
    $extensionModuleContent = @"
# SecretManagement.Sops Extension - Compiled Module
# This implements the SecretManagement vault interface

# Import parent module helpers
`$parentModulePath = Join-Path `$PSScriptRoot '..\SecretManagement.Sops.psm1'
Import-Module `$parentModulePath -Force

"@

    # Add extension Private functions
    $extensionPrivatePath = Join-Path $SourcePath 'SecretManagement.Sops.Extension\Private'
    $extensionPrivateFiles = Get-ChildItem -Path "$extensionPrivatePath/*.ps1" -ErrorAction SilentlyContinue
    foreach ($file in $extensionPrivateFiles) {
        $extensionModuleContent += "`n# region Private: $($file.BaseName)`n"
        $extensionModuleContent += Get-Content $file.FullName -Raw
        $extensionModuleContent += "`n# endregion`n"
    }

    # Add extension Public functions
    $extensionPublicPath = Join-Path $SourcePath 'SecretManagement.Sops.Extension\Public'
    $extensionPublicFiles = Get-ChildItem -Path "$extensionPublicPath/*.ps1" -ErrorAction SilentlyContinue
    foreach ($file in $extensionPublicFiles) {
        $extensionModuleContent += "`n# region Public: $($file.BaseName)`n"
        $extensionModuleContent += Get-Content $file.FullName -Raw
        $extensionModuleContent += "`n# endregion`n"
    }

    # Add Export-ModuleMember for extension
    $extensionModuleContent += "`n# Export only the 5 required SecretManagement functions`n"
    $extensionModuleContent += "Export-ModuleMember -Function 'Get-Secret', 'Get-SecretInfo', 'Test-SecretVault', 'Set-Secret', 'Remove-Secret'`n"

    Set-Content -Path $extensionModulePath -Value $extensionModuleContent -Encoding UTF8
    Write-Build Gray "  Compiled extension module with $($extensionPrivateFiles.Count) private + $($extensionPublicFiles.Count) public functions"

    # Copy manifest files
    Write-Build Gray 'Copying manifest files...'
    $sourceMainManifest = Join-Path $SourcePath "$ModuleName.psd1"
    $destMainManifest = Join-Path $BuildModulePath "$ModuleName.psd1"
    Copy-Item $sourceMainManifest $destMainManifest

    $sourceExtensionManifest = Join-Path $SourcePath 'SecretManagement.Sops.Extension\SecretManagement.Sops.Extension.psd1'
    $destExtensionManifest = Join-Path $extensionPath 'SecretManagement.Sops.Extension.psd1'
    Copy-Item $sourceExtensionManifest $destExtensionManifest

    Write-Build Green "Module compiled successfully to: $BuildModulePath"
}

# Synopsis: Run Pester tests
task Test {
    Write-Build Green 'Running Pester tests...'

    # Dependencies are automatically installed via PreToolUse hook (see CLAUDE.md)
    # To manually install dependencies, run: .\Install-SopsVaultDependencies.ps1

    # Bootstrap test data if missing (auto-generates encrypted test files)
    $testKeyFile = Join-Path $PSScriptRoot 'Tests\TestData\test-key.txt'
    if (-not (Test-Path $testKeyFile)) {
        Write-Build Yellow 'TestData not found - running setup script...'
        $setupScript = Join-Path $PSScriptRoot 'Tests\TestData\Initialize-SopsTestEnvironment.ps1'

        # Check if SOPS and age are available
        $sopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)
        $ageAvailable = $null -ne (Get-Command 'age-keygen' -ErrorAction SilentlyContinue)

        if ($sopsAvailable -and $ageAvailable) {
            & $setupScript -ErrorAction Stop
            Write-Build Green 'TestData initialized successfully'
        } else {
            Write-Build Yellow 'SOPS or age not found - tests requiring encryption will fail'
            Write-Build Yellow 'Install from: https://github.com/getsops/sops/releases and https://github.com/FiloSottile/age/releases'
        }
    }

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $TestsPath
    $pesterConfig.Run.Exit = $false
    $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = Join-Path $PSScriptRoot 'TestResults.xml'

    $result = Invoke-Pester -Configuration $pesterConfig

    if ($result.FailedCount -gt 0) {
        throw "Pester tests failed: $($result.FailedCount) failed out of $($result.TotalCount) tests"
    }

    Write-Build Green "All $($result.PassedCount) tests passed"
}

# Synopsis: Validate source module can be imported
task ValidateSource {
    Write-Build Green 'Validating source module can be imported...'

    # Remove module if already loaded
    if (Get-Module $ModuleName) {
        Remove-Module $ModuleName -Force
    }

    # Import from source
    $module = Import-Module $SourceManifestPath -Force -PassThru -ErrorAction Stop

    if (-not $module) {
        throw "Failed to import source module from $SourceManifestPath"
    }

    # Verify expected functions are available
    $exportedCommands = @($module.ExportedCommands.Keys)
    Write-Build Gray "  Source module exported $($exportedCommands.Count) commands"

    if ($exportedCommands.Count -eq 0) {
        throw 'No commands exported from source module'
    }

    # Clean up
    Remove-Module $ModuleName -Force

    Write-Build Green 'Source module import validation passed'
}

# Synopsis: Validate built module can be imported
task ValidateImport Compile, {
    Write-Build Green 'Validating built module can be imported...'

    # Import the built module
    $builtManifest = Join-Path $BuildModulePath "$ModuleName.psd1"
    Import-Module $builtManifest -Force -ErrorAction Stop

    # Verify expected functions are available
    $exportedCommands = Get-Command -Module $ModuleName
    Write-Build Gray "Module exports $($exportedCommands.Count) commands"

    # Remove the module
    Remove-Module $ModuleName -Force

    Write-Build Green 'Module import validation passed'
}

# Synopsis: Full build with compilation and validation
task Build UpdateManifest, Analyze, ValidateSource, Test, Compile, ValidateImport

# Synopsis: Quick build without tests or compilation (for rapid iteration)
task Quick UpdateManifest, Analyze

# Synopsis: Test-only task (skips analysis) - alias for Test task
task TestOnly Test
