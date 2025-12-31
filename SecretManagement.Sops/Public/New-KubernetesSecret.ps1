function New-KubernetesSecret {
    <#
    .SYNOPSIS
    Generate Kubernetes Secret YAML manifest with plain-text values.

    .DESCRIPTION
    Wrapper for kubectl create secret that generates YAML manifests with plain-text
    values in stringData field (not base64-encoded data field). This is designed for
    use with SOPS encryption, which protects the plain-text values.

    REQUIRES kubectl to be installed. No fallback implementation.

    Supports three secret types:
    - generic: Opaque secrets with key-value pairs
    - docker-registry: Docker registry authentication
    - tls: TLS certificates and keys

    .PARAMETER Name
    The name of the secret.

    .PARAMETER Namespace
    The Kubernetes namespace. Defaults to 'default'.

    .PARAMETER FromLiteral
    Hashtable of key-value pairs for generic secrets.

    .PARAMETER FromFile
    Hashtable of key=filepath pairs for generic secrets.

    .PARAMETER FromEnvFile
    Path to environment file (.env format) for generic secrets.

    .PARAMETER Type
    Secret type for generic secrets. Defaults to 'Opaque'.

    .PARAMETER DockerRegistry
    Switch to create docker-registry secret type.

    .PARAMETER DockerServer
    Docker registry server URL.

    .PARAMETER DockerCredential
    Docker registry credentials (username and password) as a PSCredential object.

    .PARAMETER DockerEmail
    Docker registry email address.

    .PARAMETER Tls
    Switch to create TLS secret type.

    .PARAMETER CertPath
    Path to certificate file for TLS secrets.

    .PARAMETER KeyPath
    Path to private key file for TLS secrets.

    .PARAMETER AsHashtable
    Return result as hashtable/OrderedDictionary instead of YAML string.

    .PARAMETER AsJson
    Return result as JSON string instead of YAML string.

    .OUTPUTS
    String - YAML manifest by default, JSON if -AsJson specified, or hashtable if -AsHashtable specified.

    .EXAMPLE
    New-KubernetesSecret -Name 'app-config' -FromLiteral @{
        'api-key' = 'secret123'
        'db-password' = 'pass456'
    }

    .EXAMPLE
    $cred = Get-Credential -UserName 'myuser'
    New-KubernetesSecret -Name 'registry-creds' -DockerRegistry `
        -DockerServer 'docker.io' `
        -DockerCredential $cred

    .EXAMPLE
    New-KubernetesSecret -Name 'tls-cert' -Tls `
        -CertPath './cert.pem' `
        -KeyPath './key.pem'

    .EXAMPLE
    New-KubernetesSecret -Name 'env-config' -FromEnvFile '.env' -AsHashtable
    #>
    [CmdletBinding(DefaultParameterSetName = 'generic')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$Namespace = 'default',

        # Generic secret parameters
        [Parameter(ParameterSetName = 'generic')]
        [hashtable]$FromLiteral,

        [Parameter(ParameterSetName = 'generic')]
        [hashtable]$FromFile,

        [Parameter(ParameterSetName = 'generic')]
        [ValidateScript({ Test-Path $_ })]
        [string]$FromEnvFile,

        [Parameter(ParameterSetName = 'generic')]
        [ValidateSet('Opaque', 'kubernetes.io/service-account-token', 'kubernetes.io/dockercfg')]
        [string]$Type = 'Opaque',

        # Docker registry parameters
        [Parameter(ParameterSetName = 'docker-registry', Mandatory)]
        [switch]$DockerRegistry,

        [Parameter(ParameterSetName = 'docker-registry')]
        [string]$DockerServer,

        [Parameter(ParameterSetName = 'docker-registry', Mandatory)]
        [PSCredential]$DockerCredential,

        [Parameter(ParameterSetName = 'docker-registry')]
        [string]$DockerEmail,

        # TLS parameters
        [Parameter(ParameterSetName = 'tls', Mandatory)]
        [switch]$Tls,

        [Parameter(ParameterSetName = 'tls', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$CertPath,

        [Parameter(ParameterSetName = 'tls', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$KeyPath,

        # Output options
        [Parameter()]
        [switch]$AsHashtable,

        [Parameter()]
        [switch]$AsJson
    )

    # Check kubectl availability (REQUIRED - no fallback)
    if (-not (Get-Command 'kubectl' -ErrorAction SilentlyContinue)) {
        throw "kubectl is required for New-KubernetesSecret. Install kubectl from https://kubernetes.io/docs/tasks/tools/"
    }

    # Build kubectl command arguments
    $kubectlArgs = @('create', 'secret')

    switch ($PSCmdlet.ParameterSetName) {
        'generic' {
            $kubectlArgs += 'generic', $Name

            if ($FromLiteral) {
                foreach ($kv in $FromLiteral.GetEnumerator()) {
                    $kubectlArgs += "--from-literal=$($kv.Key)=$($kv.Value)"
                }
            }

            if ($FromFile) {
                foreach ($kv in $FromFile.GetEnumerator()) {
                    $kubectlArgs += "--from-file=$($kv.Key)=$($kv.Value)"
                }
            }

            if ($FromEnvFile) {
                $kubectlArgs += "--from-env-file=$FromEnvFile"
            }

            if ($Type -ne 'Opaque') {
                $kubectlArgs += "--type=$Type"
            }
        }

        'docker-registry' {
            $kubectlArgs += 'docker-registry', $Name

            if ($DockerServer) {
                $kubectlArgs += "--docker-server=$DockerServer"
            }
            if ($DockerCredential) {
                $kubectlArgs += "--docker-username=$($DockerCredential.UserName)"
                # Convert SecureString password to plain text for kubectl
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DockerCredential.Password)
                try {
                    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    $kubectlArgs += "--docker-password=$plainPassword"
                }
                finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
            if ($DockerEmail) {
                $kubectlArgs += "--docker-email=$DockerEmail"
            }
        }

        'tls' {
            $kubectlArgs += 'tls', $Name
            $kubectlArgs += "--cert=$CertPath", "--key=$KeyPath"
        }
    }

    # Add common flags
    $kubectlArgs += '--dry-run=client', '-o', 'yaml', "--namespace=$Namespace"

    # Execute kubectl
    $output = & kubectl @kubectlArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        $errorMsg = $output -join "`n"
        throw "kubectl failed to create secret: $errorMsg"
    }

    # Parse the YAML output
    Import-Module powershell-yaml -ErrorAction Stop
    $secret = ($output -join "`n") | ConvertFrom-Yaml

    # Convert base64-encoded 'data' to plain-text 'stringData'
    if ($secret.data) {
        $stringData = [ordered]@{}
        foreach ($key in $secret.data.Keys) {
            $base64Value = $secret.data[$key]
            $decodedBytes = [System.Convert]::FromBase64String($base64Value)
            $stringData[$key] = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        }
        $secret.Remove('data')
        $secret['stringData'] = $stringData
    }

    # Return in requested format (default is YAML string)
    if ($AsJson) {
        return ($secret | ConvertTo-Json -Depth 10)
    }

    if ($AsHashtable) {
        return $secret
    }

    # Default: return YAML string
    return ($secret | ConvertTo-Yaml)
}
