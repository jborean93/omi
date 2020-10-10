$Script:LibPath = Join-Path -Path $PSScriptRoot -ChildPath lib

Add-Type -Namespace PSWSMan -Name Environment -MemberDefinition @'
[DllImport("libc")]
public static extern void setenv(string name, string value);

[DllImport("libc")]
public static extern void unsetenv(string name);
'@

Function setenv {
    <#
    .SYNOPSIS
    Wrapper calling setenv PInvoke method to set the process environment variables.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $Name,

        [Parameter(Position=1)]
        [AllowEmptyString()]
        $Value
    )

    [PSWSMan.Environment]::setenv($Name, $Value)
}

Function unsetenv {
    <#
    .SYNOPSIS
    Wrapper calling unsetenv PInvoke method to unset the process environment variables.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $Name
    )

    [PSWSMan.Environment]::unsetenv($Name)
}

Function Get-Distribution {
    <#
    .SYNOPSIS
    Gets the host distribution name as understood by PSWSMan.
    #>
    [CmdletBinding()]
    param ()

    $distribution = switch -Wildcard ($PSVersionTable.OS) {
        *Darwin* { 'macOS' }
        *Linux* {
            if (Test-Path -LiteralPath /etc/os-release -PathType Leaf) {
                $osRelease = @{}
                Get-Content -LiteralPath /etc/os-release | ForEach-Object -Process {
                    if (-not $_.Trim() -or -not $_.Contains('=')) {
                        return
                    }
                
                    $key, $value = $_.Split('=', 2)
                    if ($value.StartsWith('"')) {
                        $value = $value.Substring(1)
                    }
                    if ($value.EndsWith('"')) {
                        $value = $value.Substring(0, $value.Length - 1)
                    }
                    $osRelease.$key = $value
                }

                $name = ''
                foreach ($key in @('ID', 'NAME')) {
                    if ($osRelease.Contains($key) -and $osRelease.$key) {
                        $name = $osRelease.$key
                        break
                    }
                }

                switch ($name) {
                    'alpine' {
                        $version = ([Version]$osRelease.VERSION_ID).Major
                        "alpine$($version)"
                    }
                    'arch' { 'archlinux' }
                    'centos' { "centos$($osRelease.VERSION_ID)" }
                    'debian' { "debian$($osRelease.VERSION_ID)" }
                    'fedora' { "fedora$($osRelease.VERSION_ID)" }
                    'ubuntu' { "ubuntu$($osRelease.VERSION_ID)" }
                }
            }
        }
    }

    $distribution
}

Function Get-ValidDistributions {
    <#
    .SYNOPSIS
    Outputs a list of valid distributions available to PSWSMan
    #>
    [CmdletBinding()]
    param ()

    
    Get-ChildItem -LiteralPath $Script:LibPath -Directory | ForEach-Object -Process {
        $libExtension = if ($_.Name -eq 'macOS') { 'dylib' } else { 'so' }

        $libraries = Get-ChildItem -LiteralPath $_.FullName -File -Filter "*.$libExtension"
        if ($libraries) {
            $_.name
        }
    }
}

Function Disable-WSManCertVerification {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (

    )

}

Function Enable-WSManCertVerification {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        
    )

}

Function Install-WSMan {
    <#
    .SYNOPSIS
    Install the patched WSMan libs.

    .DESCRIPTION
    Install the patched WSMan libs for the current distribution.

    .PARAMETER Distribution
    Specify the distribution to install the libraries for. If not set then the current distribution will calculated.

    .EXAMPLE
    Install-WSMan

    .NOTES
    Once updated, PowerShell must be restarted for the library to be usable. This is a limitation of how the libraries
    are loaded in a process.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [String]
        $Distribution
    )

    if (-not $Distribution) {
        $Distribution = Get-Distribution

        if (-not $Distribution) {
            Write-Error -Message "Failed to find distribution for current host" -Category InvalidOperation
            return
        }
    }

    $validDistributions = Get-ValidDistributions
    if ($Distribution -notin $validDistributions) {
        $distroList = "'$($validDistributions -join "', '")'"
        $msg = "Unsupported distribution '$Distribution'. Supported distributions: $distroList"
        Write-Error -Message $msg -Category InvalidArgument 
        return
    }

    $pwshDir = Split-Path -Path ([PSObject].Assembly.Location) -Parent
    $distributionLib = Join-Path $Script:LibPath -ChildPath $Distribution
    $libExtension = if ($_.Name -eq 'macOS') { 'dylib' } else { 'so' }

    Get-ChildItem -LiteralPath $distributionLib -File -Filter "*.$libExtension" | ForEach-Object -Process {
        $destPath = Join-Path -Path $pwshDir -ChildPath $_.Name

        $change = $true
        if (Test-Path -LiteralPath $destPath) {
            $srcHash = (Get-FileHash -LiteralPath $_.Fullname -Algorithm SHA256).Hash
            $destHash = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash

            $change = $srcHash -ne $destHash
        }

        if ($change) {
            # TODO: Verify whether -WhatIf gets applied here
            Copy-Item -LiteralPath $_.Fullname -Destination $destPath
        }
    }

    # TODO: macOS, clear attributes
}
Register-ArgumentCompleter -CommandName Install-WSMan -ParameterName Distribution -ScriptBlock { Get-ValidDistributions }

$export = @{
    Function = @(
        'Disable-WSManCertVerification',
        'Enable-WSManCertVerification',
        'Install-WSMan'
    )
}
Export-ModuleMember @export
