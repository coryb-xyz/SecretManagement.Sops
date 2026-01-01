<#
.SYNOPSIS
    Main build entry point for SecretManagement.Sops

.DESCRIPTION
    This script provides a convenient entry point for running build tasks.
    It ensures InvokeBuild is available and delegates to the build definition.

.PARAMETER Task
    The build task(s) to execute. Defaults to the default task (full build).
    Available tasks:
    - . (default)     : Full build pipeline (Clean, UpdateManifest, Analyze, Test)
    - Build          : Full build with validation (UpdateManifest, Analyze, ValidateSource, Test, Compile, ValidateImport)
    - Quick          : Fast build without tests (UpdateManifest, Analyze)
    - UpdateManifest : Auto-generate FunctionsToExport (only if changed)
    - Analyze        : Run PSScriptAnalyzer only
    - ValidateSource : Validate source module can be imported
    - Test           : Run Pester tests only
    - TestOnly       : Run tests without analysis (alias for Test)
    - Compile        : Compile module into Build directory
    - ValidateImport : Validate built module can be imported
    - Clean          : Clean build artifacts

.EXAMPLE
    .\build.ps1
    Runs the default build task (full pipeline)

.EXAMPLE
    .\build.ps1 -Task Quick
    Runs a quick build without tests

.EXAMPLE
    .\build.ps1 -Task UpdateManifest, Analyze
    Updates manifest and runs analyzer only
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Task = '.'
)

# Ensure we're in the script directory
Push-Location $PSScriptRoot

try {
    # Check if InvokeBuild is available
    $invokeBuildModule = Get-Module -Name InvokeBuild -ListAvailable | Select-Object -First 1

    if (-not $invokeBuildModule) {
        Write-Warning 'InvokeBuild module not found. Installing...'
        Install-Module -Name InvokeBuild -Scope CurrentUser -Force -AllowClobber
        $invokeBuildModule = Get-Module -Name InvokeBuild -ListAvailable | Select-Object -First 1
    }

    # Import InvokeBuild
    Import-Module InvokeBuild -Force

    # Run the build using Invoke-Build cmdlet (not hardcoded path)
    Invoke-Build -Task $Task -File (Join-Path $PSScriptRoot 'SecretManagement.Sops.build.ps1')
}
finally {
    Pop-Location
}
