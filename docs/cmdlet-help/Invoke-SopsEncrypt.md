---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Invoke-SopsEncrypt

## SYNOPSIS
Wrapper for SOPS encryption operations.

## SYNTAX

```
Invoke-SopsEncrypt [-FilePath] <String> [-InPlace] [[-VaultParameters] <Hashtable>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Encrypts a file using SOPS.
Can either return encrypted content to stdout
or modify the file in-place.

## EXAMPLES

### EXAMPLE 1
```
Invoke-SopsEncrypt -FilePath 'C:\secrets\db.yaml'
```

### EXAMPLE 2
```
Invoke-SopsEncrypt -FilePath 'C:\secrets\config.yaml' -InPlace
```

## PARAMETERS

### -FilePath
The path to the file to encrypt.

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

### -InPlace
If specified, encrypts the file in-place instead of returning content to stdout.

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

### -VaultParameters
{{ Fill VaultParameters Description }}

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
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

### String - The encrypted content (when -InPlace is not specified).
## NOTES

## RELATED LINKS
