using namespace System.Security.Cryptography.X509Certificates
using namespace System.Management.Automation

$Script:LibPath = Join-Path -Path $PSScriptRoot -ChildPath lib

class X509CertificateChainAttribute : ArgumentTransformationAttribute {
    [object] Transform([EngineIntrinsics]$EngineIntrinsics, [object]$InputData) {
        # X509Certificate2Collection is an IEnumerable so we cannot use it in a switch statement or else an empty
        # collection becomes $null which we don't want.
        if ($InputData -is [X509Certificate2Collection]) {
            return $InputData
        }

        $outputData = switch($InputData) {
             { ($_ -is [X509Certificate2]) } { [X509Certificate2Collection]::new($_) }
             default {
                 throw [ArgumentTransformationMetadataException]::new(
                     "Could not convert input '$_' to a valid X509Certificate2Collection object."
                 )
             }
        }
        return $outputData
    }
}

Add-Type -Namespace PSWSMan -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public class PWSH_Version
{
    public Int32 Major;
    public Int32 Minor;
    public Int32 Build;
    public Int32 Revision;

    public static explicit operator Version(PWSH_Version v)
    {
        return new Version(v.Major, v.Minor, v.Build, v.Revision);
    }
}

[DllImport("libc")]
public static extern void setenv(string name, string value);

[DllImport("libc")]
public static extern void unsetenv(string name);

[DllImport("libmi")]
public static extern void MI_Version_Info(PWSH_Version version);

[DllImport("libpsrpclient")]
public static extern void PSRP_Version_Info(PWSH_Version version);
'@

Function exec {
    <#
    .SYNOPSIS
    Wraps a native exec call in a function so it can be set with '-ErrorAction SilentlyContinue'.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $FilePath,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [String[]]
        $Arguments
    )

    (&$FilePath @Arguments | Set-Variable output) 2>&1 | Set-Variable err
    $output
    if ($err) {
        $err | Write-Error
    }
}

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
    [PSWSMan.Native]::setenv($Name, $Value)
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
    [PSWSMan.Native]::unsetenv($Name)
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
        setenv 'OMI_SKIP_CA_CHECK' '1'
    }

    if ($CNCheck) {
        setenv 'OMI_SKIP_CN_CHECK' '1'
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
        unsetenv 'OMI_SKIP_CN_CHECK'
    }
}

Function Get-WSManVersion {
    <#
    .SYNOPSIS
    Gets the versions of the installed WSMan libraries.

    .DESCRIPTION
    Gets the versions of the libmi and libpsrpclient libraries that were specified at build time. This will only
    output a valid version if the installed libraries are ones built and installed by PSWSMan.

    .EXAMPLE
    Get-WSManVersion

    .OUTPUTS PSWSMan.Version
    [PSCustomObject]@{
        MI = [Version] The version of libmi
        PSRP = [Version] The version of libpsrpclient
    }
    #>
    [CmdletBinding()]
    param ()

    $nameMap = [Ordered]@{
        MI = 'mi'
        PSRP = 'psrpclient'
    }

    $versions = [Ordered]@{
        PSTypeName = 'PSWSMan.Version'
    }

    foreach ($map in $nameMap.GetEnumerator()) {
        $version = [PSWSMan.Native+PWSH_Version]::new()
        try {
            [PSWSMan.Native]::"$($map.Key)_Version_Info"($version)
        }
        catch [ArgumentNullException] {
            # .NET raises ArgumentNullException if the library or it's deps could not be found.
            $msg = "lib$($map.Value) could not be loaded, make sure it and its dependencies are available"
            Write-Error -Message $msg -Category NotInstalled
            $version = $null
        }
        catch [EntryPointNotFoundException] {
            # The function isn't exported which means the loaded version isn't from our custom build
            $msg = "Custom lib$($map.Value) has not been installed, have you restarted PowerShell after installing it?"
            Write-Error -Message $msg -Category NotInstalled
            $version = $null
        }

        $versions.$($map.Key) = [Version]$version
    }

    [PSCustomObject]$versions
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
    # Need to run as root
    sudo pwsh -Command 'Install-WSMan'

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
    $libExtension = if ($distribution -eq 'macOS') { 'dylib' } else { 'so' }

    $notify = $false
    Get-ChildItem -LiteralPath $distributionLib -File -Filter "*.$libExtension" | ForEach-Object -Process {
        Write-Verbose -Message "Checking to see if $($_.Name) is installed"
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

Function Register-TrustedCertificate {
    <#
    .SYNOPSIS
    Registers a certificate into the system's trusted store.

    .DESCRIPTION
    Registers a certificate, or a chain or certificates, into the trusted store for the current Linux distribution.

    .PARAMETER Name
    The name of the certificate file to use when placing it into the trusted store directory. If not set then a random
    filename with the prefix 'PSWSMan-' will be used.

    .PARAMETER Path
    Specifies the path of a certificate to register. Wildcard characters are permitted.

    .PARAMETER LiteralPath
    Specifies a path to one or more locations of certificates to register. The value of 'LiteralPath' is used exactly
    as it is typed. No characters are interpreted as wildcards.

    .PARAMETER Certificate
    The raw X509Certificate2 or X509Certificate2Collection object to register.

    .EXAMPLE Register multiple PEMs using a wildcard
    Register-TrustedCertificate -Path /tmp/*.pem

    .EXAMPLE Register 'my*host.pem' using a literal path
    Register-TrustedCertificate -LiteralPath 'my*host.pem'

    .EXAMPLE Load your own certificate chain and register as one chain
    $certs = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    $certs.Add([Security.Cryptography.X509Certificates.X509Certificate2]::new('/tmp/ca1.pem'))
    $certs.Add([Security.Cryptography.X509Certificates.X509Certificate2]::new('/tmp/ca2.pem'))

    Register-TrustedCertificate -Name MyDomainChains -Certificate $certs

    .EXAMPLE Register a certificate from a PEM encoded file as a normal user
    sudo pwsh -Command { Register-TrustedCertificate -Path /tmp/my_chain.pem }

    .NOTES
    This function needs to place files into trusted directories which typically require root access. This function
    needs to be running as root for it to succeed.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='Path')]
    param (
        [String]
        $Name,

        [Switch]
        $Sudo,

        [Parameter(Mandatory=$true, ParameterSetName='Path', ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path,

        [Parameter(Mandatory=$true, ParameterSetName='LiteralPath', ValueFromPipelineByPropertyName=$true)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $LiteralPath,

        [Parameter(Mandatory=$true, ParameterSetName='Certificate', ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [X509CertificateChainAttribute()]
        [X509Certificate2Collection]
        $Certificate
    )

    begin {
        $failed = $false
        $distribution = Get-Distribution
        if (-not $distribution) {
            Write-Error -Message "Failed to find distribution for current host" -Category InvalidOperation
            $failed = $true
            return
        }
        Write-Verbose -Message "Begin certificate registration for '$distribution'"

        # Determine the target path and refresh command based on the current distribution
        $certExtension = 'pem'
        $certPath, $refreshCommand = switch ($distribution) {
            archlinux {
                '/etc/ca-certificates/trust-source/anchors', 'update-ca-trust extract'
            }
            macOS {
                # macOS is special, we don't use the builtin LibreSSL setup and rely on brew to provide OpenSSL. This
                # means the path to the cert dir could change at any point in the future and we can't rely on default
                # system locations. Instead we use otool to figure out the linked location of openssl and use that. If
                # that fails then fallback to what should be the default '/user/local/etc/openssl@1.1/certs'.
                $libmiPath = Join-Path -Path $Script:Libpath -ChildPath 'macOS' -AdditionalChildPath 'libmi.dylib'

                $opensslPath = $null
                if (Test-Path -LiteralPath $libmiPath) {
                    $opensslPath = exec otool -L $libmiPath -ErrorAction SilentlyContinue |
                        Select-String -Pattern '\s+(\/.*libssl\..*\.dylib)\s+\(.*\)' |
                        ForEach-Object -Process { Split-Path -Path (Split-Path -Path $_.Matches[0].Groups[1]) } |
                        Select-Object -First 1
                }
                elseif (Get-Command -Name brew -CommandType Application -ErrorAction SilentlyContinue) {
                    $opensslPath = exec brew --prefix openssl -ErrorAction SilentlyContinue
                }

                if ($opensslPath) {
                    $openssl = Join-Path $opensslPath -ChildPath bin -AdditionalChildPath openssl
                    $certDirectory = exec $openssl @('version', '-d') -ErrorAction SilentlyContinue |
                        Select-String -Pattern 'OPENSSLDIR:\s+[\"|''](.*)[\"|'']$' |
                        ForEach-Object -Process { $_.Matches[0].Groups[1].Value } |
                        Select-Object -First 1
                }

                if (-not $certDirectory) {
                    $certDirectory = '/usr/local/etc/openssl@1.1/certs'
                }
                $cRehash = Join-Path -Path $opensslPath -ChildPath bin -AdditionalChildPath c_rehash

                $certDirectory, $cRehash
            }
            { $_ -like 'centos*' -or $_ -like 'fedora*' } {
                '/etc/pki/ca-trust/source/anchors', 'update-ca-trust extract'
            }
            { $_ -like 'alpine*' -or $_ -like 'debian*' -or $_ -like 'ubuntu*' } {
                # While the format of the file is the same, these distributions expect the files to have a .crt extension.
                $certExtension = 'crt'
                '/usr/local/share/ca-certificates', 'update-ca-certificates'
            }
        }
        Write-Verbose "Trust directory '$certPath' - Refresh command '$refreshCommand'"

        if (-not (Test-Path -LiteralPath $certPath)) {
            $msg = "Failed to find the expected cert trust path at '$certPath' for distribution '$distribution'"
            Write-Error -Message $msg -Category ObjectNotFound
            $failed = $true
            return
        }

        # Store the pem files
        $chainPems = [Collections.Generic.List[String]]@()
    }

    process {
        # Safeguard in case the begin block failed
        if ($failed) {
            return
        }

        $header = '-----BEGIN CERTIFICATE-----'
        $footer = '-----END CERTIFICATE-----'

        if ($PSCmdlet.ParameterSetName -in @('Path', 'LiteralPath')) {
            $Certificate = [X509Certificate2Collection]::new()
            $filePaths = [Collections.Generic.List[String]]@()

            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $provider = $null
                foreach ($rawPath in $Path) {
                    $filePaths.AddRange($PSCmdlet.GetResolvedProviderPathFromPSPath($rawPath, [ref]$provider))
                }
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
                $filePaths.Add($PSCmdlet.GetUnresolvedProviderPathFromPSPath($LiteralPath))
            }

            foreach ($filePath in $filePaths) {
                Write-Verbose -Message "Processing input certificate at '$filePath'"
                if (-not (Test-Path -LiteralPath $filePath)) {
                    Write-Error -Message "Certificate at '$filePath' does not exist." -Category ObjectNotFound
                    continue
                }

                # X509Certificate2Collection.Import() can be temperamental when trying to load multi-pem files.
                # Instead detect if it's a PEM file and load all the certs manually.
                $rawCertContent = Get-Content -LiteralPath $filePath

                if ($header -in $rawCertContent -and $footer -in $rawCertContent) {
                    foreach ($line in $rawCertContent) {
                        if (-not $line -or $line -eq $header) {
                            $currentCert = [Text.StringBuilder]::new()
                        }
                        elseif ($line -eq $footer) {
                            $certBytes = [Convert]::FromBase64String($currentCert.ToString())
                            $cert = [X509Certificate2]::new($certBytes)
                            $null = $Certificate.Add($cert)
                        }
                        else {
                            $null = $currentCert.Append($line)
                        }
                    }
                }
                else {
                    $Certificate.Import($filePath)
                }
                Write-Verbose -Message "Found $($Certificate.Count) cert(s) at '$filePath'"
            }
        }

        foreach ($cert in $Certificate) {
            Write-Verbose -Message "Processing certificate Subject: '$($cert.Subject)', Thumbprint: $($cert.Thumbprint)"
            $certBytes = $cert.Export([X509ContentType]::Cert)
            $certB64 = [Convert]::ToBase64String($certBytes, [Base64FormattingOptions]::InsertLineBreaks)
            $certB64 = $certB64 -replace "`r`n", "`n"
            $chainPems.Add("$header`n$certB64`n$footer")
        }
    }

    end {
        # Safeguard in case the begin block failed
        if ($failed) {
            return
        }
        if (-not $chainPems) {
            Write-Verbose -Message "No certificates found to import"
            return
        }

        $tempFile = [IO.Path]::GetTempFileName()
        try {
            foreach ($pem in $chainPems) {
                Add-Content -LiteralPath $tempFile -Value $pem
            }

            if (-not $Name) {
                $Name = "PSWSMan-$([IO.Path]::GetRandomFileName())"
            }

            $destCertPath = Join-Path -Path $certPath -ChildPath "$Name.$certExtension"
            if ($PSCmdlet.ShouldProcess($destCertPath, 'Register')) {
                Write-Verbose -Message "Creating trust cert file at '$destCertPath'"
                Copy-Item -LiteralPath $tempFile -Destination $destCertPath -Force

                # The command to run may contain argument, just use Invoke-Expression as the input is statically defined.
                Write-Verbose -Message "Refreshing the trusted certificate directory with '$refreshCommand'"
                Invoke-Expression -Command $refreshCommand
            }
        } finally {
            Remove-Item -LiteralPath $tempFile -Force
        }
    }
}

$export = @{
    Function = @(
        'Disable-WSManCertVerification',
        'Enable-WSManCertVerification',
        'Get-WSManVersion',
        'Install-WSMan',
        'Register-TrustedCertificate'
    )
}
Export-ModuleMember @export
