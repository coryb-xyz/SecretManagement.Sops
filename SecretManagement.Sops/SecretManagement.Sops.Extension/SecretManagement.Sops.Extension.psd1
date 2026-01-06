@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'SecretManagement.Sops.Extension.psm1'

    # Version number of this module.
    ModuleVersion        = '0.3.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID                 = 'cc263113-a583-4c9f-985c-d84ecf2489b2'

    # Author of this module
    Author               = 'SecretManagement.Sops Contributors'

    # Company or vendor of this module
    CompanyName          = 'Community'

    # Copyright statement for this module
    Copyright            = '(c) 2025 SecretManagement.Sops Contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'SecretManagement extension vault implementation for SOPS. This module is loaded by Microsoft.PowerShell.SecretManagement and should not be imported directly.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Functions to export from this module
    FunctionsToExport    = @(
        'Get-Secret',
        'Get-SecretInfo',
        'Test-SecretVault',
        'Set-Secret',
        'Remove-Secret'
    )

    # Cmdlets to export from this module
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module
    AliasesToExport      = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData          = @{
        PSData = @{
            Tags = @('SecretManagement', 'Extension')
        }
    }
}
