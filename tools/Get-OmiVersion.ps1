#!/usr/bin/env pwsh
# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)
<#
.SYNOPSIS
Gets the version of the compiled libmi library.

.PARAMETER Path
The path to the libmi library, if not set it defaults to the one used by PowerShell.

.OUTPUTS
[Version] - The version of the compiled 
#>
[CmdletBinding()]
param (
    [String]
    $Path
)

if ($Path) {
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Error "The Path specified '$Path' is not a valid file"
        return
    }

} else {
    $pwshPath = Split-Path -Path ([PSObject].Assembly.Location) -Parent
    $Path = @(Get-Item -Path (Join-Path -Path $pwshPath -ChildPath "libmi.*"))[0].FullName
}

Add-Type -Namespace MI -Name Native -MemberDefinition @"
[StructLayout(LayoutKind.Sequential)]
public class PWSH_OMI_Version
{
    public Int32 Major;
    public Int32 Minor;
    public Int32 Build;
    public Int32 Revision;

    public static explicit operator Version(PWSH_OMI_Version v)
    {
        return new Version(v.Major, v.Minor, v.Build, v.Revision);
    }
}

[DllImport("$Path")]
public static extern void MI_Version_Info(PWSH_OMI_Version version);
"@

$rawVersion = [MI.Native+PWSH_OMI_Version]::new()
[MI.Native]::MI_Version_Info($rawVersion)

[Version]$rawVersion
