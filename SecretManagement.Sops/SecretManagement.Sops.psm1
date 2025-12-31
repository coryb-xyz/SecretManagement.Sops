# SecretManagement.Sops - Module Loader
# This module auto-loads all Public and Private functions

# Dot-source all Public functions
$publicFunctions = Get-ChildItem -Path $PSScriptRoot/Public/*.ps1 -ErrorAction SilentlyContinue
foreach ($file in $publicFunctions) {
    . $file.FullName
}

# Dot-source all Private functions
$privateFunctions = Get-ChildItem -Path $PSScriptRoot/Private/*.ps1 -ErrorAction SilentlyContinue
foreach ($file in $privateFunctions) {
    . $file.FullName
}

# Export Public functions
$exportedFunctions = $publicFunctions.BaseName | ForEach-Object { $_ }
Export-ModuleMember -Function $exportedFunctions
