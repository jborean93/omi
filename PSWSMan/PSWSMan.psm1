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

    # We need to use the native setenv call as .NET keeps it's own register of env vars that are separate from the
    # process block that native libraries like libmi sees. We still set the .NET env var to keep things in sync.
    [PSWSMan.Environment]::setenv($Name, $Value)
    Set-Item -LiteralPath env:$Name -Value $Value    
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

    # We need to use the native unsetenv call as .NET keeps it's own register of env vars that are separate from the
    # process block that native libraries like libmi sees. We still unset the .NET env var to keep things in sync.
    [PSWSMan.Environment]::unsetenv($Name)
    if (Test-Path -LiteralPath env:$Name) {
        Remove-Item -LiteralPath env:$Name -Force
    }
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
    <#
    .SYNOPSIS
    Disables certificate verification globally.

    .DESCRIPTION
    Disables certificate verification for any WSMan requests globally. This can be disabled for just the CA or CN
    checks or for all checks. The absence of a switch does not enable those checks, it only disables the specific
    check requested if it was not disabled already.

    .PARAMETER CACheck
    Disables the certificate authority (CA) checks, i.e. the certificate authority chain does not need to be trusted.

    .PARAMETER CNCheck
    Disables the common name (CN) checks, i.e. the hostname does not need to match the CN or SAN on the endpoint
    certificate.

    .PARAMETER All
    Disables both the CA and CN checks.

    .EXAMPLE Disable all cert verification checks
    Disable-WSManCertVerification -All

    .EXAMPLE Disable just the CA verification checks
    Disable-WSManCertVerification -CACheck

    .NOTES
    These checks are set through environment vars which are scoped to a process and are not set to a specific
    connection. Unless you've set the specific env vars yourself then cert verification is enabled by default.
    #>
    [CmdletBinding(DefaultParameterSetName='Individual')]
    param (
        [Parameter(ParameterSetName='Individual')]
        [Switch]
        $CACheck,

        [Parameter(ParameterSetName='Individual')]
        [Switch]
        $CNCheck,

        [Parameter(ParameterSetName='All')]
        [Switch]
        $All
    )

    if ($All) {
        $CACheck = $true
        $CNCheck = $true
    }

    if ($CACheck) {
        setenv 'OMI_SKIP_CA_CHECK', '1'
    }

    if ($CNCheck) {
        setenv 'OMI_SKIP_CA_CHECK', '1'
    }
}

Function Enable-WSManCertVerification {
    <#
    .SYNOPSIS
    Enables cert verification globally.

    .DESCRIPTION
    Enables certificate verification for any WSMan requests globally. This can be enabled for just the CA or CN checks
    or for all checks. The absence of a switch does not disable those checks, it only enables the specific check
    requested  if it was not enabled already.

    .PARAMETER CACheck
    Enable the certificate authority (CA) checks, i.e. the certificate authority chain is checked for the endpoint
    certificate.

    .PARAMETER CNCheck
    Enable the common name (CN) checks, i.e. the hostname matches the CN or SAN on the endpoint certificate.

    .PARAMETER All
    Enables both the CA and CN checks.

    .EXAMPLE Enable all cert verification checks
    Enable-WSManCertVerification -All

    .EXAMPLE Enable just the CA verification checks
    Enable-WSManCertVerification -CACheck

    .NOTES
    These checks are set through environment vars which are scoped to a process and are not set to a specific
    connection. Unless you've set the specific env vars yourself then cert verification is enabled by default.
    #>
    [CmdletBinding(DefaultParameterSetName='Individual')]
    param (
        [Parameter(ParameterSetName='Individual')]
        [Switch]
        $CACheck,

        [Parameter(ParameterSetName='Individual')]
        [Switch]
        $CNCheck,

        [Parameter(ParameterSetName='All')]
        [Switch]
        $All
    )

    if ($All) {
        $CACheck = $true
        $CNCheck = $true
    }

    if ($CACheck) {
        unsetenv 'OMI_SKIP_CA_CHECK'
    }

    if ($CNCheck) {
        unsetenv 'OMI_SKIP_CA_CHECK'
    }
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
    are loaded in a process. The function will warn if one of the libraries has been changed and a restart is required.
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
    Write-Verbose -Message "Installing WSMan libs for '$Distribution'"

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

    $notify = $false
    Get-ChildItem -LiteralPath $distributionLib -File -Filter "*.$libExtension" | ForEach-Object -Process {
        $destPath = Join-Path -Path $pwshDir -ChildPath $_.Name

        $change = $true
        if (Test-Path -LiteralPath $destPath) {
            $srcHash = (Get-FileHash -LiteralPath $_.Fullname -Algorithm SHA256).Hash
            $destHash = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash

            $change = $srcHash -ne $destHash
        }

        if ($change) {
            Write-Verbose -Message "Installing $($_.Name) to '$pwshDir'"
            Copy-Item -LiteralPath $_.Fullname -Destination $destPath
            $notify = $true
        }
    }

    if ($notify) {
        $msg = 'WSMan libs have been installed, please restart your PowerShell session to enable it in PowerShell'
        Write-Warning -Message $msg
    }
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
