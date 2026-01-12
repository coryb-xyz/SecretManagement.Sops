---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Invoke-SopsUnset

## SYNOPSIS
Wrapper for SOPS unset operations.

## SYNTAX

```
Invoke-SopsUnset [-Path] <String> [-FilePath] <String> [[-VaultParameters] <Hashtable>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Removes a key or branch from a SOPS-encrypted file without fully decrypting and re-encrypting it.
Useful for deleting specific fields from complex YAML/JSON structures.

## EXAMPLES

### EXAMPLE 1
```
Invoke-SopsUnset -Path '["stringData"]["password"]' -FilePath 'C:\secrets\db.yaml'
```

### EXAMPLE 2
```
$params = @{ AgeKeyFile = 'C:\keys\vault.txt' }
Invoke-SopsUnset -Path '["stringData"]["obsolete-key"]' -FilePath 'C:\secrets\k8s.yaml' -VaultParameters $params
```

## PARAMETERS

### -Path
The SOPS JSONPath expression to unset (e.g., '\["stringData"\]\["password"\]').

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

### -FilePath
The path to the SOPS-encrypted file to modify.

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

### -VaultParameters
Optional vault parameters that may include AgeKeyFile for per-vault key configuration.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
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

### String array - The output from the SOPS command.
## NOTES
Throws an exception if the SOPS unset command fails.

## RELATED LINKS
