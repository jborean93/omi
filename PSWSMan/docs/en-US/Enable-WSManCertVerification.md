---
external help file: PSWSMan.dll-Help.xml
Module Name: PSWSMan
online version:
schema: 2.0.0
---

# Enable-WSManCertVerification

## SYNOPSIS
Enables cert verification globally.

## SYNTAX

### Individual (Default)
```
Enable-WSManCertVerification [-CACheck] [-CNCheck] [<CommonParameters>]
```

### All
```
Enable-WSManCertVerification [-All] [<CommonParameters>]
```

## DESCRIPTION
Enables certificate verification for any WSMan requests globally.
This can be enabled for just the CA or CN checks or for all checks.
The absence of a switch does not disable those checksomi, it only enables the specific check requested if it was not enabled already.

## EXAMPLES

### Example Enable all cert verification checks
```powershell
PS C:\> Enable-WSManCertVerification -All
```

Enable both the CA and CN checks.

### Example Enable just the CA verification checks
```powershell
PS C:\> Enable-WSManCertVerification -CACheck
```

Enables just the CA (Certificate Authority) checks.

## PARAMETERS

### -All
Enables both the CA and CN checks.

```yaml
Type: SwitchParameter
Parameter Sets: All
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -CACheck
Enable the certificate authority (CA) checks, i.e. the certificate authority chain is checked for the endpoint certificate.

```yaml
Type: SwitchParameter
Parameter Sets: Individual
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -CNCheck
Enable the common name (CN) checks, i.e. the hostname matches the CN or SAN on the endpoint certificate.

```yaml
Type: SwitchParameter
Parameter Sets: Individual
Aliases:

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

These checks are set through environment vars which are scoped to a process and are not set to a specific connection.
Unless you've set the specific env vars yourself then cert verification is enabled by default.

## RELATED LINKS
