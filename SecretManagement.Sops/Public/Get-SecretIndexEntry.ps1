function Get-SecretIndexEntry {
    <#
    .SYNOPSIS
    Creates an index entry for a single SOPS file.

    .DESCRIPTION
    Analyzes a SOPS file and creates a metadata entry with secret name, type,
    and Kubernetes information.

    .PARAMETER FilePath
    The full path to the SOPS file.

    .PARAMETER BasePath
    The base vault directory path.

    .PARAMETER NamingStrategy
    The naming strategy to use.

    .OUTPUTS
    Hashtable - The index entry with metadata about the secret.

    .EXAMPLE
    $entry = Get-SecretIndexEntry -FilePath 'C:\vault\apps\db\password.yaml' -BasePath 'C:\vault'
    # Returns: @{ Name='apps/db/password'; FilePath='C:\vault\apps\db\password.yaml'; Namespace='apps/db'; ShortName='password' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter()]
        [string]$NamingStrategy = 'RelativePath'
    )

    # Create the index entry
    $entry = @{
        FilePath = $FilePath
    }

    # Resolve the secret name from file path only (no decryption needed)
    $entry.Name = Resolve-SecretName -FilePath $FilePath -BasePath $BasePath -NamingStrategy $NamingStrategy

    # Extract namespace and short name from the resolved name
    # The resolved name contains the full path (e.g., "apps/foo/bar/dv1/secret")
    # Split into namespace (folder path) and short name (filename)
    $namespace = ""
    $shortName = $entry.Name

    if ($entry.Name -match '^(.+)/([^/]+)$') {
        $namespace = $matches[1]      # e.g., "apps/foo/bar/dv1"
        $shortName = $matches[2]      # e.g., "secret"
    }
    # else: file at vault root, namespace remains ""

    $entry.Namespace = $namespace
    $entry.ShortName = $shortName

    return $entry
}
