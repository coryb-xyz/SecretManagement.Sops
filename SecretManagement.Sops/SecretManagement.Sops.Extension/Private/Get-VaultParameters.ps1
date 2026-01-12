function Get-VaultParameters {
    # Function returns a hashtable of multiple vault parameters, so plural is appropriate
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns collection of parameters as hashtable')]
    <#
    .SYNOPSIS
    Gets vault parameters with defaults applied.
    #>
    param(
        [hashtable]$AdditionalParameters
    )

    $defaults = @{
        FilePattern       = '*.yaml'
        Recurse           = $false
        NamingStrategy    = 'RelativePath'
        AgeKeyFile        = $null
        RequireEncryption = $false
    }

    # Merge provided parameters with defaults
    $params = $defaults.Clone()
    if ($AdditionalParameters) {
        foreach ($key in $AdditionalParameters.Keys) {
            $params[$key] = $AdditionalParameters[$key]
        }
    }

    return $params
}
