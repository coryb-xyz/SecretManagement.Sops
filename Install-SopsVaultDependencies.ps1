<#
.SYNOPSIS
Bootstrap script to install and verify all dependencies for SecretManagement.Sops.

.DESCRIPTION
This script checks for and optionally installs all required and optional dependencies
for the SecretManagement.Sops module, including:
- External tools (SOPS, age, Azure CLI)
- Development tools (Pester, PSScriptAnalyzer)

.PARAMETER IncludeDevelopment
If specified, also checks and installs development dependencies (Pester, PSScriptAnalyzer, platyPS).

.PARAMETER Scope
The installation scope for PowerShell modules (CurrentUser or AllUsers).
Defaults to CurrentUser.

.PARAMETER SkipOptional
If specified, skips optional dependencies and only checks required ones.

.PARAMETER NonInteractive
If specified, runs in non-interactive mode (no prompts, auto-installs with defaults).

.EXAMPLE
.\Install-SopsVaultDependencies.ps1

Runs interactive setup, prompting for each optional dependency.

.EXAMPLE
.\Install-SopsVaultDependencies.ps1 -IncludeDevelopment -Scope AllUsers

Installs all dependencies including development tools for all users.

.EXAMPLE
.\Install-SopsVaultDependencies.ps1 -SkipOptional -NonInteractive

Silently checks only required dependencies without installing optional ones.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludeDevelopment,

    [Parameter()]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [Parameter()]
    [switch]$SkipOptional,

    [Parameter()]
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# Import dependency configuration
$depsPath = Join-Path $PSScriptRoot 'requiredModules.psd1'
if (-not (Test-Path $depsPath)) {
    Write-Error "Cannot find requiredModules.psd1 at $depsPath"
    exit 1
}

$deps = Import-PowerShellDataFile -Path $depsPath

Write-Host "`n=== SecretManagement.Sops Dependency Check ===" -ForegroundColor Cyan
Write-Host "This script will check and optionally install dependencies.`n" -ForegroundColor Gray

# Helper function to check external tool availability
<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Name
${3:Parameter description}

.PARAMETER VerificationCommand
${4:Parameter description}

.PARAMETER Tool
${5:Parameter description}

.EXAMPLE
${6:An example}

.NOTES
${7:General notes}
#>
function Test-ExternalTool {
    param(
        [string]$Name,
        [string]$VerificationCommand,
        [hashtable]$Tool
    )

    Write-Host "Checking for $Name..." -NoNewline

    try {
        $null = Invoke-Expression $VerificationCommand 2>&1
        Write-Host " FOUND" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host " NOT FOUND" -ForegroundColor $(if ($Tool.Required) { 'Red' } else { 'Yellow' })

        if ($Tool.Required) {
            Write-Host "`nERROR: $Name is REQUIRED but not found in PATH." -ForegroundColor Red
        }
 else {
            Write-Host "`nWARNING: $Name is optional but recommended." -ForegroundColor Yellow
        }

        Write-Host "`nInstallation Instructions for $($Tool.Description):" -ForegroundColor Cyan

        $os = if ($IsWindows -or $env:OS -match 'Windows') { 'Windows' }
        elseif ($IsMacOS) { 'macOS' }
        elseif ($IsLinux) { 'Linux' }
        else { 'Windows' }

        if ($Tool.InstallInstructions.ContainsKey($os)) {
            foreach ($instruction in $Tool.InstallInstructions[$os]) {
                Write-Host "  - $instruction" -ForegroundColor Gray
            }
        }

        Write-Host "`nProject URL: $($Tool.ProjectUrl)" -ForegroundColor Gray
        Write-Host ""

        return $false
    }
}

# Helper function to check/install PowerShell module
<#
.SYNOPSIS
${1:Short description}

.DESCRIPTION
${2:Long description}

.PARAMETER Module
${3:Parameter description}

.PARAMETER InstallScope
${4:Parameter description}

.PARAMETER Prompt
${5:Parameter description}

.EXAMPLE
${6:An example}

.NOTES
${7:General notes}
#>
function Install-PSModuleDependency {
    param(
        [hashtable]$Module,
        [string]$InstallScope,
        [bool]$Prompt
    )

    $moduleName = $Module.ModuleName
    Write-Host "Checking for $moduleName..." -NoNewline

    # Check if already installed
    $existing = Get-Module -ListAvailable -Name $moduleName |
        Where-Object { -not $Module.MinimumVersion -or $_.Version -ge $Module.MinimumVersion } |
        Select-Object -First 1

    if ($existing) {
        Write-Host " FOUND (v$($existing.Version))" -ForegroundColor Green
        return $true
    }

    Write-Host " NOT FOUND" -ForegroundColor Yellow

    # Decide whether to install
    $shouldInstall = $false
    if ($NonInteractive -and $Module.AutoInstall) {
        $shouldInstall = $true
    }
    elseif ($Prompt) {
        Write-Host "`nModule: $moduleName" -ForegroundColor Cyan
        Write-Host "  Description: $($Module.Description)" -ForegroundColor Gray
        Write-Host "  Purpose: $($Module.Purpose)" -ForegroundColor Gray
        if ($Module.MinimumVersion) {
            Write-Host "  Minimum Version: $($Module.MinimumVersion)" -ForegroundColor Gray
        }
        $response = Read-Host "`nInstall from PSGallery? (Y/N)"
        $shouldInstall = $response -match '^[Yy]'
    }

    if (-not $shouldInstall) {
        Write-Host "  Skipped installation of $moduleName" -ForegroundColor Gray
        return $false
    }

    # Install the module
    try {
        Write-Host "  Installing $moduleName from PSGallery..." -ForegroundColor Cyan

        $installParams = @{
            Name         = $moduleName
            Scope        = $InstallScope
            Force        = $true
            AllowClobber = $true  # Allow overriding existing commands if other YAML modules present
            ErrorAction  = 'Stop'
        }

        if ($Module.MinimumVersion) {
            $installParams['MinimumVersion'] = $Module.MinimumVersion
        }

        Install-Module @installParams

        # Verify
        $installed = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        if ($installed) {
            Write-Host "  Successfully installed $moduleName v$($installed.Version)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Warning "  Module installation completed but module not found"
            return $false
        }
    }
    catch {
        Write-Error "Failed to install ${moduleName}: $_"
        return $false
    }
}

# Track results
$results = @{
    ExternalTools   = @()
    OptionalModules = @()
    DevModules      = @()
    AllPassed       = $true
}

# 1. Check external tools
Write-Host "`n--- External Tools ---" -ForegroundColor Cyan
foreach ($tool in $deps.ExternalTools) {
    $found = Test-ExternalTool -Name $tool.Name -VerificationCommand $tool.VerificationCommand -Tool $tool
    $results.ExternalTools += @{
        Name     = $tool.Name
        Found    = $found
        Required = $tool.Required
    }

    if (-not $found -and $tool.Required) {
        $results.AllPassed = $false
    }
}

# 2. Check optional PowerShell modules
if (-not $SkipOptional) {
    Write-Host "`n--- Optional PowerShell Modules ---" -ForegroundColor Cyan
    foreach ($module in $deps.OptionalModules) {
        $installed = Install-PSModuleDependency -Module $module -InstallScope $Scope -Prompt (-not $NonInteractive)
        $results.OptionalModules += @{
            Name      = $module.ModuleName
            Installed = $installed
        }
    }
}

# 3. Check development modules if requested
if ($IncludeDevelopment) {
    Write-Host "`n--- Development Modules ---" -ForegroundColor Cyan
    foreach ($module in $deps.DevelopmentModules) {
        $installed = Install-PSModuleDependency -Module $module -InstallScope $Scope -Prompt (-not $NonInteractive)
        $results.DevModules += @{
            Name      = $module.ModuleName
            Installed = $installed
        }
    }
}

# 4. Summary
Write-Host "`n=== Dependency Check Summary ===" -ForegroundColor Cyan

Write-Host "`nExternal Tools:" -ForegroundColor White
foreach ($tool in $results.ExternalTools) {
    $status = if ($tool.Found) { "OK" } else { "MISSING" }
    $color = if ($tool.Found) { "Green" } elseif ($tool.Required) { "Red" } else { "Yellow" }
    $required = if ($tool.Required) { " [REQUIRED]" } else { " [optional]" }
    Write-Host "  $($tool.Name): $status$required" -ForegroundColor $color
}

if ($results.OptionalModules.Count -gt 0) {
    Write-Host "`nOptional PowerShell Modules:" -ForegroundColor White
    foreach ($mod in $results.OptionalModules) {
        $status = if ($mod.Installed) { "Installed" } else { "Not Installed" }
        $color = if ($mod.Installed) { "Green" } else { "Yellow" }
        Write-Host "  $($mod.Name): $status" -ForegroundColor $color
    }
}

if ($results.DevModules.Count -gt 0) {
    Write-Host "`nDevelopment Modules:" -ForegroundColor White
    foreach ($mod in $results.DevModules) {
        $status = if ($mod.Installed) { "Installed" } else { "Not Installed" }
        $color = if ($mod.Installed) { "Green" } else { "Yellow" }
        Write-Host "  $($mod.Name): $status" -ForegroundColor $color
    }
}

Write-Host ""

# Exit code
if ($results.AllPassed) {
    Write-Host "All required dependencies are satisfied!" -ForegroundColor Green
    exit 0
}
 else {
    Write-Host "Some required dependencies are missing. Please install them before using this module." -ForegroundColor Red
    exit 1
}
