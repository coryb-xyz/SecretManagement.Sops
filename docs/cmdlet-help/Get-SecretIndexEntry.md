---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Get-SecretIndexEntry

## SYNOPSIS
Creates an index entry for a single SOPS file.

## SYNTAX

```
Get-SecretIndexEntry [-FilePath] <String> [-BasePath] <String> [[-NamingStrategy] <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Analyzes a SOPS file and creates a metadata entry with secret name, type,
and Kubernetes information.

## EXAMPLES

### EXAMPLE 1
```
$entry = Get-SecretIndexEntry -FilePath 'C:\vault\apps\db\password.yaml' -BasePath 'C:\vault'
# Returns: @{ Name='apps/db/password'; FilePath='C:\vault\apps\db\password.yaml'; Namespace='apps/db'; ShortName='password' }
```

## PARAMETERS

### -FilePath
The full path to the SOPS file.

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

### -BasePath
The base vault directory path.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NamingStrategy
The naming strategy to use.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: RelativePath
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

### Hashtable - The index entry with metadata about the secret.
## NOTES

## RELATED LINKS
