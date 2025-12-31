function Resolve-SecretName {
    <#
    .SYNOPSIS
    Resolves a secret name from a file path based on the naming strategy.

    .DESCRIPTION
    Converts a file path to a secret name using one of three strategies:
    - RelativePath: Uses the relative path from the base directory (default)
    - FileName: Uses only the filename without extension
    - KubernetesMetadata: Uses metadata.name from K8s Secret manifests

    .PARAMETER FilePath
    The full path to the SOPS file.

    .PARAMETER BasePath
    The base vault directory path.

    .PARAMETER NamingStrategy
    The naming strategy to use (RelativePath or FileName).

    .OUTPUTS
    String - The resolved secret name.

    .EXAMPLE
    Resolve-SecretName -FilePath 'C:\secrets\db\password.yaml' -BasePath 'C:\secrets' -NamingStrategy 'RelativePath'
    # Returns: db/password
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter()]
        [ValidateSet('RelativePath', 'FileName')]
        [string]$NamingStrategy = 'RelativePath'
    )

    switch ($NamingStrategy) {
        'FileName' {
            return [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        }

        'RelativePath' {
            # Normalize paths to absolute to handle relative path inputs
            $absoluteFilePath = [System.IO.Path]::GetFullPath($FilePath)
            $absoluteBasePath = [System.IO.Path]::GetFullPath($BasePath)

            # Get relative path from base directory
            $relativePath = [System.IO.Path]::GetRelativePath($absoluteBasePath, $absoluteFilePath)

            # Remove file extension
            $relativePath = $relativePath -replace '\.(yaml|yml|json)$', ''

            # Convert backslashes to forward slashes for consistency
            $relativePath = $relativePath -replace '\\', '/'

            return $relativePath
        }
    }
}
