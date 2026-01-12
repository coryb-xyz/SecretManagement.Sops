---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Invoke-SopsDecrypt

## SYNOPSIS
Wrapper for SOPS decryption operations.

## SYNTAX

```
Invoke-SopsDecrypt [-FilePath] <String> [[-Extract] <String>] [[-VaultParameters] <Hashtable>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Decrypts a SOPS-encrypted file and optionally extracts a specific key using JSONPath.

## EXAMPLES

### EXAMPLE 1
```
Invoke-SopsDecrypt -FilePath 'C:\secrets\db.yaml'
```

### EXAMPLE 2
```
Invoke-SopsDecrypt -FilePath 'C:\secrets\config.yaml' -Extract '["database"]["password"]'
```

## PARAMETERS

### -FilePath
The path to the SOPS-encrypted file to decrypt.

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

### -Extract
Optional JSONPath expression to extract a specific value from the decrypted content.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -VaultParameters
{{ Fill VaultParameters Description }}

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

### String - The decrypted content or extracted value.
## NOTES

## RELATED LINKS
