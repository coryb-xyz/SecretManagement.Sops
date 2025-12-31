function Test-PathBasedSyntax {
    <#
    .SYNOPSIS
    Tests if a string matches path-based syntax pattern.

    .DESCRIPTION
    Detects yq-style path syntax for updating specific fields in secrets.
    Path syntax allows targeted updates like: .stringData.password: newValue

    This pattern is used by Set-Secret to distinguish between:
    - Path-based updates: .path.to.field: value
    - YAML content: multi-line YAML for patching
    - Plain strings: simple values

    .PARAMETER InputString
    The string to test for path-based syntax.

    .OUTPUTS
    [bool] - Returns $true if the string matches path-based syntax pattern, $false otherwise.

    .EXAMPLE
    Test-PathBasedSyntax -InputString ".stringData.password: newPass"
    # Returns: $true

    .EXAMPLE
    Test-PathBasedSyntax -InputString ".metadata.name: mySecret"
    # Returns: $true

    .EXAMPLE
    Test-PathBasedSyntax -InputString '.data["api-key"]: secret123'
    # Returns: $true

    .EXAMPLE
    Test-PathBasedSyntax -InputString "plain-password-value"
    # Returns: $false

    .EXAMPLE
    Test-PathBasedSyntax -InputString @"
    stringData:
      password: value
    "@
    # Returns: $false (multi-line YAML, not path syntax)

    .NOTES
    The regex pattern matches:
    - Leading dot (required): .
    - Path segments: word characters, dots, brackets
    - Colon separator: :
    - Value: anything after the colon

    Pattern: ^\s*\.[\w\.\[\]"''-]+:\s*(.*)$
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$InputString
    )

    # Regex pattern for path-based syntax
    # Matches patterns like:
    # - .stringData.password: newValue
    # - .metadata.name: mySecret
    # - .data["api-key"]: secret123
    # - .config.nested.field: value
    return $InputString -match '^\s*\.[\w\.\[\]"''-]+:\s*(.*)$'
}
