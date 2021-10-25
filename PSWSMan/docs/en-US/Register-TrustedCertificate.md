---
external help file: PSWSMan-help.xml
Module Name: PSWSMan
online version:
schema: 2.0.0
---

# Register-TrustedCertificate

## SYNOPSIS
Registers a certificate into the system's trusted store.

## SYNTAX

### Path (Default)
```
Register-TrustedCertificate [-Name <String>] -Path <String[]> [-WhatIf] [-Confirm] [<CommonParameters>]
```

### LiteralPath
```
Register-TrustedCertificate [-Name <String>] -LiteralPath <String[]> [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Certificate
```
Register-TrustedCertificate [-Name <String>] -Certificate <X509Certificate2Collection> [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Registers a certificate, or a chain or certificates, into the trusted store for the current Linux distribution.

## EXAMPLES

### EXAMPLE Register multiple PEMs using a wildcard
```powershell
PS C:\> Register-TrustedCertificate -Path /tmp/*.pem
```

### EXAMPLE Register 'my*host.pem' using a literal path
```powershell
PS C:\> Register-TrustedCertificate -LiteralPath 'my*host.pem'
```

### EXAMPLE Load your own certificate chain and register as one chain
```powershell
PS C:\> $certs = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
PS C:\> $certs.Add([Security.Cryptography.X509Certificates.X509Certificate2]::new('/tmp/ca1.pem'))
PS C:\> $certs.Add([Security.Cryptography.X509Certificates.X509Certificate2]::new('/tmp/ca2.pem'))
PS C:\> Register-TrustedCertificate -Name MyDomainChains -Certificate $certs
```

### EXAMPLE Register a certificate from a PEM encoded file as a normal user
```powershell
PS C:\> sudo pwsh -Command { Register-TrustedCertificate -Path /tmp/my_chain.pem }
```

## PARAMETERS

### -Name
The name of the certificate file to use when placing it into the trusted store directory.
If not set then the value 'PSWSMan-(sha256 hash of certs)' will be used.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Path
Specifies the path of a certificate to register.
Wildcard characters are permitted.

```yaml
Type: String[]
Parameter Sets: Path
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: True
```

### -LiteralPath
Specifies a path to one or more locations of certificates to register.
The value of 'LiteralPath' is used exactly as it is typed.
No characters are interpreted as wildcards.

```yaml
Type: String[]
Parameter Sets: LiteralPath
Aliases: PSPath

Required: True
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -Certificate
The raw X509Certificate2 or X509Certificate2Collection object to register.

```yaml
Type: X509Certificate2Collection
Parameter Sets: Certificate
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None

## NOTES
This function needs to place files into trusted directories which typically require root access.

## RELATED LINKS
