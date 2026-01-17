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

    $publicPath = Join-Path $SourcePath 'Public'
    $publicFunctions = Get-ChildItem -Path "$publicPath/*.ps1" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty BaseName

    if (-not $publicFunctions) {
        throw "No public functions found in $publicPath"
    }

    Write-Build Gray "Found $($publicFunctions.Count) public functions: $($publicFunctions -join ', ')"

    $manifest = Import-PowerShellDataFile -Path $SourceManifestPath
    $currentFunctions = $manifest.FunctionsToExport

    $needsUpdate = if ($null -eq $currentFunctions) {
        Write-Build Yellow 'Manifest has no FunctionsToExport defined'
        $true
    }
    elseif ($currentFunctions.Count -ne $publicFunctions.Count) {
        Write-Build Yellow "Function count mismatch: manifest has $($currentFunctions.Count), found $($publicFunctions.Count)"
        $true
    }
    elseif (Compare-Object -ReferenceObject $publicFunctions -DifferenceObject $currentFunctions) {
        Write-Build Yellow 'Function list has changed'
        $true
    }
    else {
        $false
    }

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

    # Filter out .psd1 manifest formatting issues (Update-ModuleManifest generates non-compliant formatting)
    $manifestFormattingRules = @('PSAlignAssignmentStatement', 'PSAvoidTrailingWhitespace', 'PSUseConsistentIndentation')
    $results = Invoke-ScriptAnalyzer @analyzerParams | Where-Object {
        -not ($_.ScriptPath -like '*.psd1' -and $_.RuleName -in $manifestFormattingRules)
    }

    if ($results) {
        $results | Format-Table -AutoSize | Out-Host
    }

    $errors = @($results | Where-Object Severity -EQ 'Error')
    $warnings = @($results | Where-Object Severity -EQ 'Warning')
    $info = @($results | Where-Object Severity -EQ 'Information')

    if ($warnings.Count -gt 0) {
        Write-Build Yellow "Found $($warnings.Count) warning(s)"
    }
    if ($info.Count -gt 0) {
        Write-Build Gray "Found $($info.Count) informational message(s)"
    }
    if ($errors.Count -gt 0) {
        throw "PSScriptAnalyzer found $($errors.Count) error(s)"
    }

    Write-Build Green 'PSScriptAnalyzer passed (no errors)'
}

<#
.SYNOPSIS
    Collects PowerShell function files and wraps their content in region markers.

.DESCRIPTION
    Reads all .ps1 files from the specified path and concatenates their content,
    wrapping each file in a region marker for the compiled module output.

.PARAMETER BasePath
    The directory path containing .ps1 function files.

.PARAMETER RegionPrefix
    The prefix to use in region markers (e.g., 'Private' or 'Public').

.OUTPUTS
    Hashtable with Content (string) and Files (FileInfo array) properties.
#>
function Get-CompiledFunctionContent {
    param(
        [string]$BasePath,
        [string]$RegionPrefix
    )

    $content = ''
    $files = Get-ChildItem -Path "$BasePath/*.ps1" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content += "`n# region ${RegionPrefix}: $($file.BaseName)`n"
        $content += Get-Content $file.FullName -Raw
        $content += "`n# endregion`n"
    }

    return @{
        Content = $content
        Files = $files
    }
}

# Synopsis: Compile module into Build directory
task Compile Clean, {
    Write-Build Green 'Compiling module...'

    $null = New-Item -ItemType Directory -Path $BuildModulePath -Force
    $extensionPath = Join-Path $BuildModulePath 'SecretManagement.Sops.Extension'
    $null = New-Item -ItemType Directory -Path $extensionPath -Force
    Write-Build Gray "Created build directory: $BuildModulePath"

    # Compile main module
    Write-Build Gray 'Compiling main module...'
    $mainModulePath = Join-Path $BuildModulePath "$ModuleName.psm1"

    $privatePath = Join-Path $SourcePath 'Private'
    $publicPath = Join-Path $SourcePath 'Public'

    $privateResult = Get-CompiledFunctionContent -BasePath $privatePath -RegionPrefix 'Private'
    $publicResult = Get-CompiledFunctionContent -BasePath $publicPath -RegionPrefix 'Public'

    $publicFunctionNames = ($publicResult.Files.BaseName | ForEach-Object { "'$_'" }) -join ', '

    $mainModuleContent = @"
# $ModuleName - Compiled Module
# This is a compiled version combining all Public and Private functions
$($privateResult.Content)
$($publicResult.Content)
# Export public functions
Export-ModuleMember -Function @($publicFunctionNames)
"@

    Set-Content -Path $mainModulePath -Value $mainModuleContent -Encoding UTF8
    Write-Build Gray "  Compiled main module with $($privateResult.Files.Count) private + $($publicResult.Files.Count) public functions"

    # Compile extension module
    Write-Build Gray 'Compiling extension module...'
    $extensionModulePath = Join-Path $extensionPath 'SecretManagement.Sops.Extension.psm1'

    $extensionPrivatePath = Join-Path $SourcePath 'SecretManagement.Sops.Extension\Private'
    $extensionPublicPath = Join-Path $SourcePath 'SecretManagement.Sops.Extension\Public'

    $extPrivateResult = Get-CompiledFunctionContent -BasePath $extensionPrivatePath -RegionPrefix 'Private'
    $extPublicResult = Get-CompiledFunctionContent -BasePath $extensionPublicPath -RegionPrefix 'Public'

    $extensionModuleContent = @"
# SecretManagement.Sops Extension - Compiled Module
# This implements the SecretManagement vault interface

# Import parent module helpers
`$parentModulePath = Join-Path `$PSScriptRoot '..\SecretManagement.Sops.psm1'
Import-Module `$parentModulePath -Force
$($extPrivateResult.Content)
$($extPublicResult.Content)
# Export only the 5 required SecretManagement functions
Export-ModuleMember -Function 'Get-Secret', 'Get-SecretInfo', 'Test-SecretVault', 'Set-Secret', 'Remove-Secret'
"@

    Set-Content -Path $extensionModulePath -Value $extensionModuleContent -Encoding UTF8
    Write-Build Gray "  Compiled extension module with $($extPrivateResult.Files.Count) private + $($extPublicResult.Files.Count) public functions"

    # Copy manifest files
    Write-Build Gray 'Copying manifest files...'
    Copy-Item (Join-Path $SourcePath "$ModuleName.psd1") (Join-Path $BuildModulePath "$ModuleName.psd1")
    Copy-Item (Join-Path $SourcePath 'SecretManagement.Sops.Extension\SecretManagement.Sops.Extension.psd1') (Join-Path $extensionPath 'SecretManagement.Sops.Extension.psd1')

    # Copy help files if they exist
    $sourceHelpPath = Join-Path $SourcePath 'en-US'
    if (Test-Path $sourceHelpPath) {
        Write-Build Gray 'Copying help files...'
        $destHelpPath = Join-Path $BuildModulePath 'en-US'
        $null = New-Item -ItemType Directory -Path $destHelpPath -Force
        Copy-Item "$sourceHelpPath\*" $destHelpPath -Recurse -Force
        Write-Build Gray "  Copied help files to: $destHelpPath"
    }

    Write-Build Green "Module compiled successfully to: $BuildModulePath"
}

# Synopsis: Run Pester tests
task Test {
    Write-Build Green 'Running Pester tests...'

    # Bootstrap test data if missing
    $testKeyFile = Join-Path $PSScriptRoot 'Tests\TestData\test-key.txt'
    if (-not (Test-Path $testKeyFile)) {
        Write-Build Yellow 'TestData not found - running setup script...'
        $setupScript = Join-Path $PSScriptRoot 'Tests\TestData\Initialize-SopsTestEnvironment.ps1'

        $sopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)
        $ageAvailable = $null -ne (Get-Command 'age-keygen' -ErrorAction SilentlyContinue)

        if ($sopsAvailable -and $ageAvailable) {
            & $setupScript -ErrorAction Stop
            Write-Build Green 'TestData initialized successfully'
        }
        else {
            Write-Build Yellow 'SOPS or age not found - tests requiring encryption will fail'
            Write-Build Yellow 'Install from: https://github.com/getsops/sops/releases and https://github.com/FiloSottile/age/releases'
        }
    }

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $TestsPath
    $pesterConfig.Run.Exit = $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true'
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

    if (Get-Module $ModuleName) {
        Remove-Module $ModuleName -Force
    }

    $module = Import-Module $SourceManifestPath -Force -PassThru -ErrorAction Stop

    if (-not $module) {
        throw "Failed to import source module from $SourceManifestPath"
    }

    $exportedCommands = @($module.ExportedCommands.Keys)
    Write-Build Gray "  Source module exported $($exportedCommands.Count) commands"

    if ($exportedCommands.Count -eq 0) {
        throw 'No commands exported from source module'
    }

    Remove-Module $ModuleName -Force
    Write-Build Green 'Source module import validation passed'
}

# Synopsis: Validate built module can be imported
task ValidateImport Compile, {
    Write-Build Green 'Validating built module can be imported...'

    $builtManifest = Join-Path $BuildModulePath "$ModuleName.psd1"
    Import-Module $builtManifest -Force -ErrorAction Stop

    $exportedCommands = Get-Command -Module $ModuleName
    Write-Build Gray "Module exports $($exportedCommands.Count) commands"

    Remove-Module $ModuleName -Force
    Write-Build Green 'Module import validation passed'
}

# Synopsis: Generate external help files with platyPS
task GenerateHelp {
    Write-Build Green 'Generating external help documentation with platyPS...'

    if (-not (Get-Module -ListAvailable -Name platyPS)) {
        Write-Build Yellow 'platyPS module not found - installing...'
        Install-Module -Name platyPS -Scope CurrentUser -Force -SkipPublisherCheck
    }

    Import-Module platyPS -Force

    $helpPath = Join-Path $SourcePath 'en-US'
    if (-not (Test-Path $helpPath)) {
        $null = New-Item -ItemType Directory -Path $helpPath -Force
        Write-Build Gray "Created help directory: $helpPath"
    }

    if (Get-Module $ModuleName) {
        Remove-Module $ModuleName -Force
    }

    Import-Module $SourceManifestPath -Force

    $commands = Get-Command -Module $ModuleName -CommandType Function
    if ($commands.Count -eq 0) {
        Write-Build Yellow 'No commands found to generate help for'
        return
    }

    Write-Build Gray "Generating help for $($commands.Count) functions..."

    $markdownPath = Join-Path $PSScriptRoot 'docs' 'cmdlet-help'
    if (-not (Test-Path $markdownPath)) {
        $null = New-Item -ItemType Directory -Path $markdownPath -Force
    }

    try {
        New-MarkdownHelp -Module $ModuleName -OutputFolder $markdownPath -Force -ErrorAction Stop | Out-Null
        Write-Build Gray "  Generated/updated markdown help in: $markdownPath"
    }
    catch {
        Write-Build Yellow "  Markdown generation warning: $_"
    }

    try {
        New-ExternalHelp -Path $markdownPath -OutputPath $helpPath -Force -ErrorAction Stop | Out-Null
        Write-Build Green "  Generated MAML help file: $helpPath\$ModuleName-help.xml"
    }
    catch {
        Write-Build Yellow "  MAML generation warning: $_"
    }

    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
    Write-Build Green 'Help documentation generated successfully'
}

# Synopsis: Full build with compilation and validation
task Build UpdateManifest, Analyze, ValidateSource, Test, Compile, ValidateImport

# Synopsis: Complete build including help documentation
task BuildWithDocs UpdateManifest, Analyze, ValidateSource, Test, GenerateHelp, Compile, ValidateImport

# Synopsis: Quick build without tests or compilation (for rapid iteration)
task Quick UpdateManifest, Analyze

# Synopsis: Test-only task (skips analysis) - alias for Test task
task TestOnly Test
