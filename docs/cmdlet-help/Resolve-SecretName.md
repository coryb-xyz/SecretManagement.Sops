---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Resolve-SecretName

## SYNOPSIS
Resolves a secret name from a file path based on the naming strategy.

## SYNTAX

```
Resolve-SecretName [-FilePath] <String> [-BasePath] <String> [[-NamingStrategy] <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Converts a file path to a secret name using one of three strategies:
- RelativePath: Uses the relative path from the base directory (default)
- FileName: Uses only the filename without extension
- KubernetesMetadata: Uses metadata.name from K8s Secret manifests

## EXAMPLES

### EXAMPLE 1
```
Resolve-SecretName -FilePath 'C:\secrets\db\password.yaml' -BasePath 'C:\secrets' -NamingStrategy 'RelativePath'
# Returns: db/password
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
The naming strategy to use (RelativePath or FileName).

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

### String - The resolved secret name.
## NOTES

## RELATED LINKS
