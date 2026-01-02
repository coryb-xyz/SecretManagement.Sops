# Test Helper Utilities for SecretManagement.Sops
# This module provides helper functions for testing SOPS write operations

<#
.SYNOPSIS
    Test helper utilities for SecretManagement.Sops write support tests.

.DESCRIPTION
    Provides reusable functions for:
    - Verifying SOPS encryption
    - Validating file structures
    - Creating test secrets
    - Cleaning up test data
    - Asserting YAML content
#>

function Test-SopsEncrypted {
    <#
    .SYNOPSIS
        Verifies that a file is SOPS-encrypted.

    .DESCRIPTION
        Checks if a file contains SOPS encryption metadata and encrypted content.

    .PARAMETER FilePath
        Path to the file to check.

    .EXAMPLE
        Test-SopsEncrypted -FilePath 'C:\secrets\test.yaml'

    .OUTPUTS
        Boolean - $true if file is SOPS-encrypted, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return $false
    }

    $content = Get-Content $FilePath -Raw

    # Check for SOPS metadata section
    $hasSopsMetadata = $content -match 'sops:'

    # Check for SOPS version
    $hasSopsVersion = $content -match 'version:\s*\d+'

    # Check for encrypted data (ENC[...] format)
    $hasEncryptedData = $content -match 'ENC\['

    return ($hasSopsMetadata -and $hasSopsVersion -and $hasEncryptedData)
}

function Get-SopsDecryptedContent {
    <#
    .SYNOPSIS
        Decrypts a SOPS file and returns the content.

    .DESCRIPTION
        Uses the SOPS binary to decrypt a file and returns the decrypted YAML content.

    .PARAMETER FilePath
        Path to the SOPS-encrypted file.

    .EXAMPLE
        $content = Get-SopsDecryptedContent -FilePath 'C:\secrets\test.yaml'

    .OUTPUTS
        String - Decrypted YAML content
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $sopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)
    if (-not $sopsAvailable) {
        throw "SOPS binary not found in PATH"
    }

    try {
        $decrypted = & sops -d $FilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "SOPS decryption failed: $decrypted"
        }
        return $decrypted -join "`n"
    }
 catch {
        throw "Failed to decrypt file: $_"
    }
}

function Assert-SopsFileValid {
    <#
    .SYNOPSIS
        Asserts that a file is valid SOPS-encrypted YAML and can be decrypted.

    .DESCRIPTION
        Performs comprehensive validation:
        - File exists
        - Contains SOPS metadata
        - Can be decrypted by SOPS
        - Contains expected keys (optional)

    .PARAMETER FilePath
        Path to the SOPS file.

    .PARAMETER ExpectedKeys
        Optional array of keys that should exist in the decrypted content.

    .EXAMPLE
        Assert-SopsFileValid -FilePath 'C:\secrets\test.yaml'

    .EXAMPLE
        Assert-SopsFileValid -FilePath 'C:\secrets\db.yaml' -ExpectedKeys @('host', 'password')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ExpectedKeys
    )

    # Check file exists
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    # Check SOPS encryption
    if (-not (Test-SopsEncrypted -FilePath $FilePath)) {
        throw "File is not SOPS-encrypted: $FilePath"
    }

    # Verify decryption works
    try {
        $decrypted = Get-SopsDecryptedContent -FilePath $FilePath
    }
 catch {
        throw "File cannot be decrypted: $_"
    }

    # Check expected keys if provided
    if ($ExpectedKeys) {
        foreach ($key in $ExpectedKeys) {
            if ($decrypted -notmatch "$key\s*:") {
                throw "Expected key '$key' not found in decrypted content"
            }
        }
    }

    Write-Verbose "SOPS file validation passed: $FilePath"
}

function New-TestSecretName {
    <#
    .SYNOPSIS
        Generates a unique test secret name.

    .DESCRIPTION
        Creates a unique secret name with optional prefix for test isolation.

    .PARAMETER Prefix
        Optional prefix for the secret name. Default is 'test'.

    .EXAMPLE
        $name = New-TestSecretName
        # Returns: test-3f2504e0-4f89-11d3-9a0c-0305e82c3301

    .EXAMPLE
        $name = New-TestSecretName -Prefix 'write-test'
        # Returns: write-test-3f2504e0-4f89-11d3-9a0c-0305e82c3301

    .OUTPUTS
        String - Unique test secret name
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prefix = 'test'
    )

    return "$Prefix-$(New-Guid)"
}

function New-TestKubernetesSecret {
    <#
    .SYNOPSIS
        Creates a test Kubernetes Secret manifest hashtable.

    .DESCRIPTION
        Generates a properly structured Kubernetes Secret manifest
        for use in tests.

    .PARAMETER Name
        Name of the Kubernetes Secret.

    .PARAMETER Namespace
        Namespace for the secret. Default is 'default'.

    .PARAMETER StringData
        Hashtable of string data keys and values.

    .EXAMPLE
        $k8sSecret = New-TestKubernetesSecret -Name 'test-secret' -StringData @{ 'key1' = 'value1' }

    .OUTPUTS
        Hashtable - Kubernetes Secret manifest
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Namespace = 'default',

        [Parameter(Mandatory = $true)]
        [hashtable]$StringData
    )

    return @{
        apiVersion = 'v1'
        kind       = 'Secret'
        metadata   = @{
            name      = $Name
            namespace = $Namespace
        }
        type       = 'Opaque'
        stringData = $StringData
    }
}

function Get-SopsFileMetadatum {
    <#
    .SYNOPSIS
        Extracts SOPS metadata from an encrypted file.

    .DESCRIPTION
        Parses the SOPS metadata section to retrieve encryption information.

    .PARAMETER FilePath
        Path to the SOPS-encrypted file.

    .EXAMPLE
        $metadata = Get-SopsFileMetadata -FilePath 'C:\secrets\test.yaml'
        $metadata.version

    .OUTPUTS
        Hashtable - SOPS metadata
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $content = Get-Content $FilePath -Raw

    # Extract SOPS version
    $versionMatch = [regex]::Match($content, 'version:\s*(\d+)')
    $version = if ($versionMatch.Success) { [int]$versionMatch.Groups[1].Value } else { $null }

    # Check for age encryption
    $hasAge = $content -match 'age:'

    # Check for Azure Key Vault encryption
    $hasAzure = $content -match 'azure_kv:'

    return @{
        Version          = $version
        HasAge           = $hasAge
        HasAzureKeyVault = $hasAzure
        IsEncrypted      = (Test-SopsEncrypted -FilePath $FilePath)
    }
}

function Wait-ForFileOperation {
    <#
    .SYNOPSIS
        Waits for a file operation to complete with retries.

    .DESCRIPTION
        Useful for handling file system delays in tests.
        Retries a script block until it succeeds or times out.

    .PARAMETER ScriptBlock
        Script block to execute.

    .PARAMETER TimeoutSeconds
        Maximum time to wait in seconds. Default is 5.

    .PARAMETER RetryIntervalMs
        Interval between retries in milliseconds. Default is 100.

    .EXAMPLE
        Wait-ForFileOperation -ScriptBlock { Test-Path 'C:\secrets\test.yaml' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 5,

        [Parameter(Mandatory = $false)]
        [int]$RetryIntervalMs = 100
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $result = & $ScriptBlock
            if ($result) {
                return $result
            }
        }
 catch {
            # Suppress errors during retry
        }

        Start-Sleep -Milliseconds $RetryIntervalMs
    }

    throw "Operation timed out after $TimeoutSeconds seconds"
}

function Initialize-SopsTestVault {
    <#
    .SYNOPSIS
        Sets up a complete SOPS test vault with all required configuration.

    .DESCRIPTION
        Consolidates common test setup patterns:
        - Imports required modules
        - Auto-configures age key environment variable
        - Creates test vault directory
        - Generates .sops.yaml configuration
        - Registers SecretManagement vault

    .PARAMETER VaultName
        Name for the test vault. Default: 'SopsTestVault'.

    .PARAMETER TestDrive
        Base path for test files (typically $TestDrive from Pester).

    .PARAMETER VaultSubPath
        Subdirectory name under TestDrive for this vault. Default: 'secrets'.

    .PARAMETER TestDataPath
        Path to TestData directory containing test-key.txt. Default: auto-detected from PSScriptRoot.

    .OUTPUTS
        Hashtable with vault configuration:
        - VaultName: The registered vault name
        - VaultPath: Full path to vault directory
        - TestKeyFile: Path to age key file
        - AgePublicKey: The age public key string

    .EXAMPLE
        $vault = Initialize-SopsTestVault -TestDrive $TestDrive
        # Use $vault.VaultName for Get-Secret, Set-Secret, etc.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestDrive,

        [Parameter(Mandatory = $false)]
        [string]$VaultName = 'SopsTestVault',

        [Parameter(Mandatory = $false)]
        [string]$VaultSubPath = 'secrets',

        [Parameter(Mandatory = $false)]
        [string]$TestDataPath
    )

    # 1. Auto-detect TestData path if not provided
    if (-not $TestDataPath) {
        $TestDataPath = Join-Path $PSScriptRoot 'TestData'
    }

    # 2. Import required modules
    $modulePath = Join-Path $PSScriptRoot '..\SecretManagement.Sops\SecretManagement.Sops.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop

    # 3. Auto-configure SOPS_AGE_KEY_FILE environment variable
    $testKeyFile = Join-Path $TestDataPath 'test-key.txt'
    if ((Test-Path $testKeyFile) -and (-not $env:SOPS_AGE_KEY_FILE)) {
        $env:SOPS_AGE_KEY_FILE = $testKeyFile
    }

    # 4. Create test vault directory
    $vaultPath = Join-Path $TestDrive $VaultSubPath
    New-Item -Path $vaultPath -ItemType Directory -Force | Out-Null

    # 5. Extract age public key and create .sops.yaml
    $agePublicKey = $null
    if (Test-Path $testKeyFile) {
        $ageKeyContent = Get-Content $testKeyFile -Raw
        if ($ageKeyContent -match 'public key: (.+)') {
            $agePublicKey = $Matches[1].Trim()

            # Create .sops.yaml in vault directory
            $sopsConfig = @"
creation_rules:
  - path_regex: \.yaml$
    age: $agePublicKey
"@
            Set-Content -Path (Join-Path $vaultPath '.sops.yaml') -Value $sopsConfig
        }
    }

    # 6. Unregister vault if it already exists (cleanup from previous test runs)
    try {
        Unregister-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore errors - vault may not exist
    }

    # 7. Register the vault
    Register-SecretVault -Name $VaultName -ModuleName $modulePath -VaultParameters @{
        Path        = $vaultPath
        FilePattern = '*.yaml'
    }

    # 8. Return vault configuration
    return @{
        VaultName    = $VaultName
        VaultPath    = $vaultPath
        TestKeyFile  = $testKeyFile
        AgePublicKey = $agePublicKey
        ModulePath   = $modulePath
    }
}

function Unregister-SopsTestVault {
    <#
    .SYNOPSIS
        Safely unregisters a test vault.

    .DESCRIPTION
        Unregisters a SecretManagement vault with error suppression.
        Intended for use in AfterAll blocks.

    .PARAMETER VaultName
        Name of the vault to unregister.

    .EXAMPLE
        AfterAll {
            Unregister-SopsTestVault -VaultName $script:VaultName
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )

    try {
        Unregister-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
        Write-Verbose "Unregistered test vault: $VaultName"
    }
    catch {
        # Suppress errors - vault may not exist or may already be unregistered
        Write-Verbose "Failed to unregister vault $VaultName (may not exist): $_"
    }
}

<#
.SYNOPSIS
    Saves the current SOPS-related environment state for later restoration

.OUTPUTS
    Hashtable containing the saved environment state

.EXAMPLE
    $state = Save-SopsEnvironment
    try {
        $env:SOPS_AGE_KEY_FILE = $testKey
        # ... test code ...
    } finally {
        Restore-SopsEnvironment -State $state
    }
#>
function Save-SopsEnvironment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        SOPS_AGE_KEY_FILE = $env:SOPS_AGE_KEY_FILE
        SOPS_AGE_RECIPIENTS = $env:SOPS_AGE_RECIPIENTS
    }
}

<#
.SYNOPSIS
    Restores SOPS-related environment variables from saved state

.PARAMETER State
    Hashtable containing saved environment state from Save-SopsEnvironment

.EXAMPLE
    Restore-SopsEnvironment -State $savedState
#>
function Restore-SopsEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
    )

    # Restore SOPS_AGE_KEY_FILE
    if ($null -eq $State.SOPS_AGE_KEY_FILE) {
        Remove-Item Env:\SOPS_AGE_KEY_FILE -ErrorAction SilentlyContinue
    }
    else {
        $env:SOPS_AGE_KEY_FILE = $State.SOPS_AGE_KEY_FILE
    }

    # Restore SOPS_AGE_RECIPIENTS
    if ($null -eq $State.SOPS_AGE_RECIPIENTS) {
        Remove-Item Env:\SOPS_AGE_RECIPIENTS -ErrorAction SilentlyContinue
    }
    else {
        $env:SOPS_AGE_RECIPIENTS = $State.SOPS_AGE_RECIPIENTS
    }
}

<#
.SYNOPSIS
    Generates a new AGE key for testing with proper isolation

.PARAMETER Path
    Path where the key file should be created (typically in $TestDrive)

.OUTPUTS
    Hashtable containing KeyFile path and PublicKey string

.EXAMPLE
    $key = New-TestAgeKey -Path (Join-Path $TestDrive 'test-key.txt')
    $env:SOPS_AGE_KEY_FILE = $key.KeyFile
#>
function New-TestAgeKey {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Generate the key
    $keyOutput = & age-keygen -o $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate AGE key: $keyOutput"
    }

    # Extract public key from output
    $publicKeyLine = $keyOutput | Where-Object { $_ -match 'public key:' } | Select-Object -First 1
    if ($publicKeyLine -and $publicKeyLine -match 'public key:\s*(.+)') {
        $publicKey = $matches[1].Trim()
    }
    else {
        throw "Failed to extract public key from age-keygen output"
    }

    return @{
        KeyFile = $Path
        PublicKey = $publicKey
    }
}

<#
.SYNOPSIS
    Registers a test vault with guaranteed unique name and verification

.PARAMETER BaseName
    Base name for the vault (will be suffixed with GUID for uniqueness)

.PARAMETER ModulePath
    Path to the SOPS vault module

.PARAMETER VaultParameters
    Hashtable of vault-specific parameters

.OUTPUTS
    String containing the registered vault name

.EXAMPLE
    $vaultName = New-IsolatedTestVault -BaseName 'SopsTest' -ModulePath $modulePath -VaultParameters @{ Path = $path; FilePattern = '*.yaml' }
#>
function New-IsolatedTestVault {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$BaseName,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters
    )

    # Generate unique vault name
    $vaultName = "$BaseName-$(New-Guid)"

    # Paranoid check for collision
    $existingVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
    if ($existingVault) {
        throw "Vault name collision detected: $vaultName already exists"
    }

    # Register vault
    try {
        $registerParams = @{
            Name = $vaultName
            ModuleName = $ModulePath
            VaultParameters = $VaultParameters
        }
        Register-SecretVault @registerParams -ErrorAction Stop
    }
    catch {
        throw "Failed to register vault '$vaultName': $_"
    }

    # Verify registration
    $registeredVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
    if (-not $registeredVault) {
        throw "Vault registration verification failed: $vaultName not found after registration"
    }

    Write-Verbose "Successfully registered isolated test vault: $vaultName"
    return $vaultName
}

<#
.SYNOPSIS
    Unregisters a test vault with retries and verification

.PARAMETER VaultName
    Name of the vault to unregister

.PARAMETER MaxAttempts
    Maximum number of unregistration attempts (default: 3)

.EXAMPLE
    Remove-IsolatedTestVault -VaultName $testVaultName
#>
function Remove-IsolatedTestVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter()]
        [int]$MaxAttempts = 3
    )

    if ([string]::IsNullOrWhiteSpace($VaultName)) {
        Write-Warning "Remove-IsolatedTestVault called with empty vault name"
        return
    }

    $attempt = 0
    $unregistered = $false

    while ($attempt -lt $MaxAttempts -and -not $unregistered) {
        $attempt++
        try {
            Unregister-SecretVault -Name $VaultName -ErrorAction Stop
            $unregistered = $true
            Write-Verbose "Successfully unregistered vault: $VaultName (attempt $attempt)"
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Warning "Failed to unregister vault '$VaultName' after $MaxAttempts attempts: $_"
            }
            else {
                Write-Verbose "Unregister attempt $attempt failed, retrying after delay: $_"
                Start-Sleep -Milliseconds 100
            }
        }
    }

    # Verify cleanup
    $vault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    if ($vault) {
        Write-Warning "Vault '$VaultName' still registered after cleanup attempts"
    }
}

<#
.SYNOPSIS
    Cleans up orphaned test vaults from previous test runs

.PARAMETER VaultNamePattern
    Regex pattern to match test vault names (default: '^Sops.*Test.*')

.EXAMPLE
    Remove-OrphanedTestVaults
    Remove-OrphanedTestVaults -VaultNamePattern '^MyTestVault.*'
#>
function Remove-OrphanedTestVaults {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$VaultNamePattern = '^Sops.*Test.*'
    )

    $orphanedVaults = Get-SecretVault | Where-Object { $_.Name -match $VaultNamePattern }

    if ($orphanedVaults) {
        Write-Warning "Found $($orphanedVaults.Count) orphaned test vault(s) from previous runs:"
        foreach ($vault in $orphanedVaults) {
            Write-Warning "  - $($vault.Name)"
            try {
                Unregister-SecretVault -Name $vault.Name -ErrorAction Stop
                Write-Verbose "    Successfully cleaned up orphaned vault: $($vault.Name)"
            }
            catch {
                Write-Warning "    Failed to clean up orphaned vault '$($vault.Name)': $_"
            }
        }
    }
    else {
        Write-Verbose "No orphaned test vaults found matching pattern: $VaultNamePattern"
    }
}

<#
.SYNOPSIS
    Initializes test data if missing by running the setup script

.PARAMETER Force
    Force re-initialization even if test data exists

.OUTPUTS
    Boolean - True if test data is ready, False if prerequisites missing

.EXAMPLE
    if (Initialize-TestDataIfMissing) {
        # Test data ready, proceed with tests
    }
#>
function Initialize-TestDataIfMissing {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$Force
    )

    $testDataPath = Join-Path $PSScriptRoot 'TestData'
    $testKeyFile = Join-Path $testDataPath 'test-key.txt'
    $setupScript = Join-Path $testDataPath 'Initialize-SopsTestEnvironment.ps1'

    # Check if test data exists - need BOTH key AND encrypted files
    $keyMissing = -not (Test-Path $testKeyFile)

    # Check for at least one encrypted file as a smoke test
    $sampleEncryptedFile = Join-Path $testDataPath 'simple-secret.yaml'
    $encryptedFilesMissing = -not (Test-Path $sampleEncryptedFile)

    $needsSetup = $Force -or $keyMissing -or $encryptedFilesMissing

    if ($needsSetup) {
        # Check prerequisites
        $sopsAvailable = $null -ne (Get-Command 'sops' -ErrorAction SilentlyContinue)
        $ageAvailable = $null -ne (Get-Command 'age-keygen' -ErrorAction SilentlyContinue)

        if (-not $sopsAvailable -or -not $ageAvailable) {
            $message = @"
Missing test prerequisites. Please install:
- SOPS: https://github.com/getsops/sops/releases
- age: https://github.com/FiloSottile/age/releases

Or skip tests requiring these tools.
"@
            Write-Warning $message
            return $false
        }

        # Run setup script
        Write-Verbose "Initializing test data..."
        try {
            & $setupScript -Mode UnitTest -ErrorAction Stop
            return $true
        }
        catch {
            Write-Warning "Failed to initialize test data: $_"
            return $false
        }
    }

    return $true
}

# Export all functions
Export-ModuleMember -Function @(
    'Test-SopsEncrypted'
    'Get-SopsDecryptedContent'
    'Assert-SopsFileValid'
    'New-TestSecretName'
    'New-TestKubernetesSecret'
    'Get-SopsFileMetadata'
    'Wait-ForFileOperation'
    'Initialize-SopsTestVault'
    'Unregister-SopsTestVault'
    'Save-SopsEnvironment'
    'Restore-SopsEnvironment'
    'New-TestAgeKey'
    'New-IsolatedTestVault'
    'Remove-IsolatedTestVault'
    'Remove-OrphanedTestVaults'
    'Initialize-TestDataIfMissing'
)
