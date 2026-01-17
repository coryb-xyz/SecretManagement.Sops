function Resolve-SecretName {
    <#
    .SYNOPSIS
    Resolves a secret name from a file path based on the naming strategy.

    .DESCRIPTION
    Converts a file path to a secret name using one of two strategies:
    - RelativePath: Uses the relative path from the base directory (default)
    - FileName: Uses only the filename without extension

    .PARAMETER FilePath
    The full path to the SOPS file.

    .PARAMETER BasePath
    The base vault directory path.

    .PARAMETER NamingStrategy
    The naming strategy to use. Defaults to 'RelativePath'.

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
            $absoluteFilePath = [System.IO.Path]::GetFullPath($FilePath)
            $absoluteBasePath = [System.IO.Path]::GetFullPath($BasePath)
            $relativePath = [System.IO.Path]::GetRelativePath($absoluteBasePath, $absoluteFilePath)

            # Remove extension and normalize path separators
            $relativePath = $relativePath -replace '\.(yaml|yml|json)$', ''
            $relativePath = $relativePath -replace '\\', '/'

            return $relativePath
        }
    }
}
