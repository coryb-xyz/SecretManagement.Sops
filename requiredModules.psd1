@{
    # PowerShell module dependencies
    # No optional runtime dependencies required (users parse YAML with their preferred parser)
    OptionalModules    = @()

    # External tool dependencies
    # These are external binaries that must be installed separately
    ExternalTools      = @(
        @{
            Name                = 'sops'
            Description         = 'Mozilla SOPS - Secrets OPerationS encryption tool'
            Purpose             = 'Core encryption/decryption functionality'
            Required            = $true
            MinimumVersion      = '3.7.0'
            InstallInstructions = @{
                Windows = @(
                    'WinGet: winget install SecretsOPerationS.SOPS'
                    'Chocolatey: choco install sops'
                    'Scoop: scoop install sops'
                    'Manual: Download from https://github.com/mozilla/sops/releases'
                )
                Linux   = @(
                    'Debian/Ubuntu: Download .deb from https://github.com/mozilla/sops/releases'
                    'RHEL/CentOS: Download .rpm from https://github.com/mozilla/sops/releases'
                    'Arch: pacman -S sops'
                    'Manual: Download binary from https://github.com/mozilla/sops/releases'
                )
                macOS   = @(
                    'Homebrew: brew install sops'
                    'MacPorts: port install sops'
                )
            }
            VerificationCommand = 'sops --version'
            ProjectUrl          = 'https://github.com/mozilla/sops'
        }
        @{
            Name                = 'age'
            Description         = 'Modern encryption tool (alternative to PGP)'
            Purpose             = 'Optional encryption backend for SOPS (alternative to Azure Key Vault)'
            Required            = $false
            MinimumVersion      = '1.0.0'
            InstallInstructions = @{
                Windows = @(
                    'WinGet: winget install FiloSottile.age'
                    'Chocolatey: choco install age'
                    'Scoop: scoop install age'
                    'Manual: Download from https://github.com/FiloSottile/age/releases'
                )
                Linux   = @(
                    'Debian/Ubuntu: apt install age'
                    'RHEL/CentOS: Download from https://github.com/FiloSottile/age/releases'
                    'Arch: pacman -S age'
                )
                macOS   = @(
                    'Homebrew: brew install age'
                )
            }
            VerificationCommand = 'age --version'
            ProjectUrl          = 'https://github.com/FiloSottile/age'
        }
        @{
            Name                = 'az'
            Description         = 'Azure CLI'
            Purpose             = 'Optional encryption backend for SOPS via Azure Key Vault'
            Required            = $false
            MinimumVersion      = '2.0.0'
            InstallInstructions = @{
                Windows = @(
                    'WinGet: winget install Microsoft.AzureCLI'
                    'MSI Installer: https://aka.ms/installazurecliwindows'
                )
                Linux   = @(
                    'Debian/Ubuntu: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
                    'RHEL/CentOS: https://learn.microsoft.com/cli/azure/install-azure-cli-linux'
                )
                macOS   = @(
                    'Homebrew: brew install azure-cli'
                )
            }
            VerificationCommand = 'az --version'
            ProjectUrl          = 'https://learn.microsoft.com/cli/azure/'
        }
    )

    # Build/Development dependencies
    # These are only needed for development and testing
    DevelopmentModules = @(
        @{
            ModuleName     = 'Pester'
            MinimumVersion = '5.3.0'
            Description    = 'PowerShell testing framework'
            Purpose        = 'Running unit and integration tests'
            InstallFrom    = 'PSGallery'
            Required       = $false
            AutoInstall    = $false
        }
        @{
            ModuleName     = 'PSScriptAnalyzer'
            MinimumVersion = '1.20.0'
            Description    = 'PowerShell script analyzer and linter'
            Purpose        = 'Code quality and best practices validation'
            InstallFrom    = 'PSGallery'
            Required       = $false
            AutoInstall    = $false
        }
        @{
            ModuleName     = 'platyPS'
            MinimumVersion = '0.14.0'
            Description    = 'Markdown-based help file generator'
            Purpose        = 'Generating external help documentation'
            InstallFrom    = 'PSGallery'
            Required       = $false
            AutoInstall    = $false
        }
        @{
            ModuleName     = 'InvokeBuild'
            MinimumVersion = '5.10.0'
            Description    = 'Build automation tool for PowerShell'
            Purpose        = 'Automating build tasks (manifest updates, testing, validation)'
            InstallFrom    = 'PSGallery'
            Required       = $false
            AutoInstall    = $false
        }
    )
}
