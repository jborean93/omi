---
external help file: PSWSMan-help.xml
Module Name: PSWSMan
online version:
schema: 2.0.0
---

# Install-WSMan

## SYNOPSIS
Install the patched WSMan libs.

## SYNTAX

```
Install-WSMan [[-Distribution] <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Install the patched WSMan libs for the current distribution.

## EXAMPLES

### EXAMPLE 1
```powershell
# Need to run as root
PS C:\> sudo pwsh -Command 'Install-WSMan'
```

## PARAMETERS

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Distribution
Deprecated and no longer used.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

## OUTPUTS

### None

## NOTES
Once updated, PowerShell must be restarted for the library to be usable.
This is a limitation of how the libraries are loaded in a process.
The function will warn if one of the libraries has been changed and a restart is required.

## RELATED LINKS
