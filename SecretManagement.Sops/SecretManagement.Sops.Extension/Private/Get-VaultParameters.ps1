function Get-VaultParameters {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
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
