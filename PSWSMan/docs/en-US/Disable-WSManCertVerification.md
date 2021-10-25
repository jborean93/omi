---
external help file: PSWSMan.dll-Help.xml
Module Name: PSWSMan
online version:
schema: 2.0.0
---

# Disable-WSManCertVerification

## SYNOPSIS
Disables certificate verification globally.

## SYNTAX

### Individual (Default)
```
Disable-WSManCertVerification [-CACheck] [-CNCheck] [<CommonParameters>]
```

### All
```
Disable-WSManCertVerification [-All] [<CommonParameters>]
```

## DESCRIPTION
Disables certificate verification for any WSMan requests globally.
This can be disabled for just the CA or CN checks or for all checks.
The absence of a switch does not enable those checks, it only disables the specific check requested if it was not disabled already.

## EXAMPLES

### Example Disable all cert verification checks
```powershell
PS C:\> Disable-WSManCertVerification -All
```

Disable both the CA and CN checks.

### Example Disable just the CA verification checks
```powershell
PS C:\> Disable-WSManCertVerification -CACheck
```

Disables just the CA (Certificate Authority) checks.

## PARAMETERS

### -All
Disables both the CA and CN checks.

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
Disables the certificate authority (CA) checks, i.e. the certificate authority chain does not need to be trusted.

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
Disables the common name (CN) checks, i.e. the hostname does not need to match the CN or SAN on the endpoint certificate.

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
