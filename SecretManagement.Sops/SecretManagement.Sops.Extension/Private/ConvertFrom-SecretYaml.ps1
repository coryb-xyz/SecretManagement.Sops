function ConvertFrom-SecretYaml {
    <#
    .SYNOPSIS
    Returns the raw decrypted YAML content as-is.

    .DESCRIPTION
    Simply returns the decrypted YAML string without any parsing or type conversion.
    Users can parse the YAML with their preferred YAML parser.

    This keeps the module simple: decrypt SOPS files and return the raw content.

    .PARAMETER YamlContent
    The raw YAML string content (decrypted from SOPS).

    .OUTPUTS
    String - The raw YAML content.

    .EXAMPLE
    ConvertFrom-SecretYaml -YamlContent "username: admin`npassword: secret"
    # Returns: "username: admin`npassword: secret"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$YamlContent
    )

    # Return raw YAML string as-is
    # Users can parse with their preferred YAML parser
    return $YamlContent
}
