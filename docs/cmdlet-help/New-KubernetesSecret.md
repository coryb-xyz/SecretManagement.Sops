---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# New-KubernetesSecret

## SYNOPSIS
Generate Kubernetes Secret YAML manifest with plain-text values.

## SYNTAX

### generic (Default)
```
New-KubernetesSecret [-Name] <String> [-Namespace <String>] [-FromLiteral <Hashtable>] [-FromFile <Hashtable>]
 [-FromEnvFile <String>] [-Type <String>] [-AsHashtable] [-AsJson] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### docker-registry
```
New-KubernetesSecret [-Name] <String> [-Namespace <String>] [-DockerRegistry] [-DockerServer <String>]
 -DockerCredential <PSCredential> [-DockerEmail <String>] [-AsHashtable] [-AsJson]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### tls
```
New-KubernetesSecret [-Name] <String> [-Namespace <String>] [-Tls] -CertPath <String> -KeyPath <String>
 [-AsHashtable] [-AsJson] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Wrapper for kubectl create secret that generates YAML manifests with plain-text
values in stringData field (not base64-encoded data field).
This is designed for
use with SOPS encryption, which protects the plain-text values.

REQUIRES kubectl to be installed.
No fallback implementation.

Supports three secret types:
- generic: Opaque secrets with key-value pairs
- docker-registry: Docker registry authentication
- tls: TLS certificates and keys

## EXAMPLES

### EXAMPLE 1
```
New-KubernetesSecret -Name 'app-config' -FromLiteral @{
    'api-key' = 'secret123'
    'db-password' = 'pass456'
}
```

### EXAMPLE 2
```
$cred = Get-Credential -UserName 'myuser'
New-KubernetesSecret -Name 'registry-creds' -DockerRegistry `
    -DockerServer 'docker.io' `
    -DockerCredential $cred
```

### EXAMPLE 3
```
New-KubernetesSecret -Name 'tls-cert' -Tls `
    -CertPath './cert.pem' `
    -KeyPath './key.pem'
```

### EXAMPLE 4
```
New-KubernetesSecret -Name 'env-config' -FromEnvFile '.env' -AsHashtable
```

## PARAMETERS

### -Name
The name of the secret.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Namespace
The Kubernetes namespace.
Defaults to 'default'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Default
Accept pipeline input: False
Accept wildcard characters: False
```

### -FromLiteral
Hashtable of key-value pairs for generic secrets.

```yaml
Type: Hashtable
Parameter Sets: generic
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -FromFile
Hashtable of key=filepath pairs for generic secrets.

```yaml
Type: Hashtable
Parameter Sets: generic
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -FromEnvFile
Path to environment file (.env format) for generic secrets.

```yaml
Type: String
Parameter Sets: generic
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Type
Secret type for generic secrets.
Defaults to 'Opaque'.

```yaml
Type: String
Parameter Sets: generic
Aliases:

Required: False
Position: Named
Default value: Opaque
Accept pipeline input: False
Accept wildcard characters: False
```

### -DockerRegistry
Switch to create docker-registry secret type.

```yaml
Type: SwitchParameter
Parameter Sets: docker-registry
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DockerServer
Docker registry server URL.

```yaml
Type: String
Parameter Sets: docker-registry
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DockerCredential
Docker registry credentials (username and password) as a PSCredential object.

```yaml
Type: PSCredential
Parameter Sets: docker-registry
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DockerEmail
Docker registry email address.

```yaml
Type: String
Parameter Sets: docker-registry
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Tls
Switch to create TLS secret type.

```yaml
Type: SwitchParameter
Parameter Sets: tls
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -CertPath
Path to certificate file for TLS secrets.

```yaml
Type: String
Parameter Sets: tls
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -KeyPath
Path to private key file for TLS secrets.

```yaml
Type: String
Parameter Sets: tls
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AsHashtable
Return result as hashtable/OrderedDictionary instead of YAML string.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -AsJson
Return result as JSON string instead of YAML string.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### String - YAML manifest by default, JSON if -AsJson specified, or hashtable if -AsHashtable specified.
## NOTES

## RELATED LINKS
