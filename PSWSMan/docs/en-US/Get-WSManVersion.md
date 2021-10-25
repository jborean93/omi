---
external help file: PSWSMan.dll-Help.xml
Module Name: PSWSMan
online version:
schema: 2.0.0
---

# Get-WSManVersion

## SYNOPSIS
Gets the versions of the installed WSMan libraries.

## SYNTAX

```
Get-WSManVersion [<CommonParameters>]
```

## DESCRIPTION
Gets the versions of the libmi and libpsrpclient libraries that were specified at build time.
This will only output a valid version if the installed libraries are ones built and installed by PSWSMan.

## EXAMPLES

### Example 1
```powershell
PS C:\> Get-WSManVersion
```

Get the version of the OMI and PSRPClient library installed.

## PARAMETERS

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

## OUTPUTS

### PSWSMan.WSManVersion

The `WSManVersion` info containing the `Version` of the `MI` and `PSRP` library.

## NOTES

## RELATED LINKS
