function Resolve-SecretNameWithNamespace {
    <#
    .SYNOPSIS
    Resolves a secret name with namespace support and collision detection.

    .DESCRIPTION
    Implements intelligent name resolution with two-tier matching:
    1. Exact full path match (e.g., "apps/foo/bar/dv1/secret")
    2. Short name match with collision detection (e.g., "secret")

    .PARAMETER Name
    The secret name to resolve (can be full path or short name).

    .PARAMETER Index
    The secret index array containing all secret entries.

    .OUTPUTS
    Hashtable with:
    - Type: 'ExactMatch' | 'ShortNameMatch' | 'Collision' | 'NotFound'
    - Entry: The matched entry (for single matches)
    - Entries: Array of matched entries (for collisions)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [array]$Index
    )

    # Priority 1: Try exact full path match
    $exactMatch = $Index | Where-Object { $_.Name -eq $Name }
    if ($exactMatch) {
        return @{
            Type  = 'ExactMatch'
            Entry = $exactMatch
        }
    }

    # Priority 2: Try short name match (backward compatibility)
    $shortNameMatches = @($Index | Where-Object { $_.ShortName -eq $Name })

    if ($shortNameMatches.Count -eq 0) {
        return @{
            Type = 'NotFound'
        }
    }

    if ($shortNameMatches.Count -eq 1) {
        return @{
            Type  = 'ShortNameMatch'
            Entry = $shortNameMatches[0]
        }
    }

    # Multiple matches - collision detected
    return @{
        Type    = 'Collision'
        Entries = $shortNameMatches
    }
}
