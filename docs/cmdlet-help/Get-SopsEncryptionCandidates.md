---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Get-SopsEncryptionCandidates

## SYNOPSIS
Discovers files that should be encrypted according to .sops.yaml configuration.

## SYNTAX

```
Get-SopsEncryptionCandidates [-Path] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Scans the vault directory for files matching .sops.yaml creation_rules that
are not yet encrypted with SOPS.
This helps identify plaintext files that
should be migrated to encrypted storage.

The function replicates SOPS matching logic:
1.
First matching rule wins (process rules in order)
2.
File must match path_regex
3.
If encrypted_regex is defined, file must contain matching keys
4.
Files matching unencrypted_suffix patterns are excluded (plaintext working copies)
5.
Already-encrypted files are excluded

## EXAMPLES

### EXAMPLE 1
```
Get-SopsEncryptionCandidates -Path 'C:\secrets'
# Returns: @('C:\secrets\config.yaml', 'C:\secrets\api-key.yaml')
```

### EXAMPLE 2
```
# Migration workflow
$candidates = Get-SopsEncryptionCandidates -Path 'C:\secrets'
foreach ($candidateFile in $candidates) {
    Write-Host "Encrypting: $candidateFile"
    sops --encrypt --in-place $candidateFile
}
```

### EXAMPLE 3
```
# CI/CD validation
$unencrypted = Get-SopsEncryptionCandidates -Path $env:SECRETS_DIR
if ($unencrypted.Count -gt 0) {
    throw "Security violation: Found unencrypted secret files"
}
```

## PARAMETERS

### -Path
Path to the vault root directory containing .sops.yaml.

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

### String[] - Array of absolute file paths that are candidates for encryption.
## NOTES
Requires .sops.yaml to exist in Path.
Returns empty array if not found.
Uses 'sops filestatus' for reliable encryption detection.
Requires SOPS binary to be available in PATH.
File patterns are automatically derived from path_regex patterns in .sops.yaml.
Always searches recursively through all subdirectories.

## RELATED LINKS
