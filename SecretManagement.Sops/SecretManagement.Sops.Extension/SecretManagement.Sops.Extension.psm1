# SecretManagement.Sops Extension Module - Loader
# This module implements the required SecretManagement vault functions

# Import parent module helpers
$parentModulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops.psm1'
Import-Module $parentModulePath -Force

# Dot-source all Public functions (extension interface)
$publicFunctions = Get-ChildItem -Path $PSScriptRoot/Public/*.ps1 -ErrorAction SilentlyContinue
foreach ($file in $publicFunctions) {
    . $file.FullName
}

# Dot-source all Private functions (internal helpers)
$privateFunctions = Get-ChildItem -Path $PSScriptRoot/Private/*.ps1 -ErrorAction SilentlyContinue
foreach ($file in $privateFunctions) {
    . $file.FullName
}

# Export only the 5 required SecretManagement functions
Export-ModuleMember -Function 'Get-Secret', 'Get-SecretInfo', 'Test-SecretVault', 'Set-Secret', 'Remove-Secret'
