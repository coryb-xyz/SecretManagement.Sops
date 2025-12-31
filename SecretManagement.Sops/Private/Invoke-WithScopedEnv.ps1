function Invoke-WithScopedEnv {
    <#
    .SYNOPSIS
    Executes a script block with temporarily scoped environment variables.

    .DESCRIPTION
    Saves current environment variable values, sets new values, executes the script block,
    and restores original values even if the script block throws an error.

    This function is useful for temporarily setting environment variables needed by external
    commands (like SOPS) without polluting the global environment or affecting other operations.

    .PARAMETER EnvVars
    Hashtable of environment variables to set. Keys are variable names (without $env: prefix).
    Values are the new values to set. Use $null to unset a variable.

    .PARAMETER ScriptBlock
    The script block to execute with the scoped environment.

    .EXAMPLE
    Invoke-WithScopedEnv -EnvVars @{ SOPS_AGE_KEY_FILE = 'C:\keys\vault1.txt' } -ScriptBlock {
        & sops --decrypt secret.yaml
    }

    .EXAMPLE
    Invoke-WithScopedEnv -EnvVars @{ VAR1 = 'value1'; VAR2 = 'value2' } -ScriptBlock {
        & some-command
    }

    .NOTES
    Uses Process scope to ensure changes only affect the current process and its children.
    The finally block ensures cleanup even if the script block throws an exception.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvVars,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    # Save original values
    $originalValues = @{}
    foreach ($key in $EnvVars.Keys) {
        $originalValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    }

    try {
        # Set new values
        foreach ($key in $EnvVars.Keys) {
            $value = $EnvVars[$key]
            [Environment]::SetEnvironmentVariable($key, $value, 'Process')
        }

        # Execute the script block
        & $ScriptBlock
    }
    finally {
        # Restore original values
        foreach ($key in $originalValues.Keys) {
            [Environment]::SetEnvironmentVariable($key, $originalValues[$key], 'Process')
        }
    }
}
