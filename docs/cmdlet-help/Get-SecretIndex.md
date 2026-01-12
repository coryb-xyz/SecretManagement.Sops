---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Get-SecretIndex

## SYNOPSIS
Builds an index of all SOPS files in the vault directory.

## SYNTAX

```
Get-SecretIndex [-Path] <String> [[-FilePattern] <String>] [[-Recurse] <Boolean>] [[-NamingStrategy] <String>]
 [[-RequireEncryption] <Boolean>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Scans the vault directory for SOPS files matching the file pattern and
creates a complete index with metadata for each secret.

## EXAMPLES

### EXAMPLE 1
```
Get-SecretIndex -Path 'C:\secrets' -FilePattern '*.yaml' -Recurse $true
```

### EXAMPLE 2
```
Get-SecretIndex -Path 'C:\secrets' -RequireEncryption $true
```

## PARAMETERS

### -Path
The vault directory path.

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

### -FilePattern
The file pattern to match (e.g., '*.yaml').

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: *.yaml
Accept pipeline input: False
Accept wildcard characters: False
```

### -Recurse
Whether to search subdirectories recursively.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: False
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
Position: 4
Default value: RelativePath
Accept pipeline input: False
Accept wildcard characters: False
```

### -RequireEncryption
Filter to only include SOPS-encrypted files.
When enabled, files without SOPS
metadata and files matching unencrypted_suffix patterns from .sops.yaml are excluded.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
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

### Array - Array of index entries (hashtables).
## NOTES

## RELATED LINKS
