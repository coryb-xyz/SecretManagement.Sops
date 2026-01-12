---
external help file: SecretManagement.Sops-help.xml
Module Name: SecretManagement.Sops
online version:
schema: 2.0.0
---

# Test-SopsAvailable

## SYNOPSIS
Tests if the SOPS binary is available in the system PATH.

## SYNTAX

```
Test-SopsAvailable [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Checks for the presence of the 'sops' executable by attempting to run 'sops --version'.

## EXAMPLES

### EXAMPLE 1
```
if (Test-SopsAvailable) {
    Invoke-SopsEncrypt -FilePath './secret.yaml' -InPlace
}
else {
    Write-Warning "SOPS is not installed. Install from https://github.com/getsops/sops/releases"
}
```

## PARAMETERS

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

### Boolean - Returns $true if SOPS is available, $false otherwise.
## NOTES

## RELATED LINKS
