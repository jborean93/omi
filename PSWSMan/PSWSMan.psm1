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

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PSWSMan
{
    public class Native
    {
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

        [DllImport("libc")]
        public static extern IntPtr gnu_get_libc_version();

        [DllImport("libmi")]
        public static extern void MI_Version_Info(PWSH_Version version);

        [DllImport("libpsrpclient")]
        public static extern void PSRP_Version_Info(PWSH_Version version);

        private delegate uint OpenSSL_version_num_ptr();

        public static uint OpenSSL_version_num(string[] libSSLPaths)
        {
            IntPtr lib = LoadLibrary(libSSLPaths);
            if (lib == IntPtr.Zero)
                return 0;

            try
            {
                // OpenSSL_version_num was introduced in 1.1.x, use SSLeay for older versions.
                string[] functionNames = {"OpenSSL_version_num", "SSLeay"};

                foreach (string name in functionNames)
                {
                    IntPtr functionAddr = IntPtr.Zero;
                    try
                    {
                        functionAddr = NativeLibrary.GetExport(lib, name);
                    }
                    catch (EntryPointNotFoundException) {}

                    if (functionAddr == IntPtr.Zero)
                        continue;

                    var function = (OpenSSL_version_num_ptr)Marshal.GetDelegateForFunctionPointer(
                        functionAddr, typeof(OpenSSL_version_num_ptr));
                    return function();                    
                }

                return 0;
            }
            finally {
                NativeLibrary.Free(lib);
            }
        }

        private delegate IntPtr OpenSSL_version_ptr(int t);

        public static string OpenSSL_version(string[] libSSLPaths, int t)
        {
            IntPtr lib = LoadLibrary(libSSLPaths);
            if (lib == IntPtr.Zero)
                return null;

            try
            {
                IntPtr functionAddr = IntPtr.Zero;

                try
                {
                    functionAddr = NativeLibrary.GetExport(lib, "OpenSSL_version");
                }
                catch (EntryPointNotFoundException) {}

                if (functionAddr == IntPtr.Zero)
                    return null;

                var function = (OpenSSL_version_ptr)Marshal.GetDelegateForFunctionPointer(
                    functionAddr, typeof(OpenSSL_version_ptr));

                return Marshal.PtrToStringAuto(function(t));
            }
            finally {
                NativeLibrary.Free(lib);
            }
        }

        private static IntPtr LoadLibrary(string[] loadPaths)
        {
            foreach(string path in loadPaths)
            {
                IntPtr handle = IntPtr.Zero;
                try
                {
                    if (NativeLibrary.TryLoad(path, out handle))
                        return handle;
                }
                catch
                {
                    // TryLoad can actually through an exception so we just ignore it and continue on.
                    continue;
                }
            }

            return IntPtr.Zero;
        }
    }
}
'@

Function exec {
    <#
    .SYNOPSIS
    Wraps a native exec call and output as separate streams for manual handling
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

    $psi = [Diagnostics.ProcessStartInfo]@{
        FileName = $FilePath
        Arguments = ($Arguments -join ' ')
        RedirectStandardError = $true
        RedirectStandardOutput = $true
    }
    $proc = [Diagnostics.Process]::Start($psi)

    $stdout = [Text.StringBuilder]::new()
    $stderr = [Text.StringBuilder]::new()
    $eventParams = @{
        InputObject = $proc
        Action = {
            if (-not [System.String]::IsNullOrEmpty($EventArgs.Data)) {
                $Event.MessageData.AppendLine($EventArgs.Data)
            }
        }
    }
    $stdoutEvent = Register-ObjectEvent @eventParams -EventName 'OutputDataReceived' -MessageData $stdout
    $stderrEvent = Register-ObjectEvent @eventParams -EventName 'ErrorDataReceived' -MessageData $stderr

    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    $proc.WaitForExit()

    Unregister-Event -SourceIdentifier $stdoutEvent.Name
    Unregister-Event -SourceIdentifier $stderrEvent.Name


    [PSCustomObject]@{
        Stdout = $stdout.ToString()
        Stderr = $stderr.ToString()
        ExitCode = $proc.ExitCode
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

Function Get-OpenSSLInfo {
    <#
    .SYNOPSIS
    Gets the OpenSSL version and SSL dir that is currently installed.
    #>
    [CmdletBinding()]
    param (
        [String[]]
        $LibSSL
    )

    $distribution = Get-Distribution

    $sslPaths = if ($LibSSL) {
        $LibSSL
    }
    elseif ($distribution -eq 'macOS') {
        @(
            'libssl',
            'libssl.dylib',
            'libssl.1.1.dylib',
            'libssl.10.dylib',
            'libssl.1.0.0.dylib',
            'libssl.3.dylib'
        )
    }
    else {
        @(
            'libssl',
            'libssl.so',
            'libssl.so.1.1',
            'libssl.so.10',
            'libssl.so.1.0.0',
            'libssl.so.3'
        )
    }
    Write-Verbose -Message "Getting OpenSSL version for '$($sslPaths -join "', '")'"

    $versionNum = [PSWSMan.Native]::OpenSSL_version_num($sslPaths)

    # MNNFFPPS: major minor fix patch status
    # For major=1 patch refers to the letter as a number, e.g. 1 == 'a', 2 == 'b', etc
    # We don't care about status
    $major = ($versionNum -band 0xF0000000) -shr 28
    $minor = ($versionNum -band 0x0FF00000) -shr 20
    $fix = ($versionNum -band 0x000FF000) -shr 12
    $patch = ($versionNum -band 0x00000FF0) -shr 4

    $version = [Version]::new($major, $minor, $fix, $patch)

    $sslDir = [PSWSMan.Native]::OpenSSL_version($sslPaths, 4)  # OPENSSL_DIR
    $sslDir = if ($sslDir) {
        $sslDir |
            Select-String -Pattern 'OPENSSLDIR:\s+[\"|''](.*)[\"|'']$' |
            ForEach-Object -Process { $_.Matches[0].Groups[1].Value } |
            Select-Object -First 1
    }

    [PSCustomObject]@{
        Version = $version
        SSLDir = $sslDir
    }
}

Function Get-MacOSOpenSSL {
    <#
    .SYNOPSIS
    Gets the libcrypto and libssl paths to use on macOS. It gets the path from the brew install openssl package and
    falls back to the port install package. We cannot use the LibreSSL version distributed by Apple as that is old
    and isn't compatible with libmi.
    #>
    [CmdletBinding()]
    param ()

    $libCrypto = $null
    $libSSL = $null

    if (Get-Command -Name brew -CommandType Application -ErrorAction SilentlyContinue) {
        $brewInfo = exec brew --prefix openssl
        $msg = "Attempting to get OpenSSL info with brew --prefix openssl`nSTDOUT: {0}`nSTDERR: {1}`nRC: {2}" -f (
            $brewInfo.Stdout, $brewInfo.Stderr, $brewInfo.ExitCode)
        Write-Verbose -Message $msg

        if ($brewInfo.ExitCode -eq 0) {
            $brewLibCrypto = Join-Path -Path $brewInfo.Stdout.Trim() lib libcrypto.dylib
            if (Test-Path -LiteralPath $brewLibCrypto) {
                Write-Verbose "Brew libcrypto exists at '$brewLibCrypto'"
                $libCrypto = $brewLibCrypto
            }

            $brewLibSSL = Join-Path -Path $brewInfo.Stdout.Trim() lib libssl.dylib
            if (Test-Path -LiteralPath $brewLibSSL) {
                Write-Verbose "Brew libssl exists at '$brewLibCrypto'"
                $libSSL = $brewLibSSL`
            }
        }
    }

    if (
        -not ($libCrypto -and $libSSL) -and
        (Get-Command -Name port -CommandType Application -ErrorAction SilentlyContinue)
    ) {
        $portInfo = exec port contents openssl
        Write-Verbose -Message "Attempting to get OpenSSL info port contents openssl"

        $portLibSSL = $null
        $portLibCrypto = $null
        
        $portInfo.Stdout -split '\r?\n' | ForEach-Object -Process {
            $line = $_.Trim()
            if (-not $line.StartsWith('/') -or ($portLibSSL -and $portLibCrypto)) {
                return
            }

            if ($line -like '*/libssl.dylib') {
                $portLibSSL = $line
            }
            elseif ($line -like '*/libcrypto.dylib') {
                $portLibCrypto = $line
            }
        }

        if ($portLibCrypto -and (Test-Path -LiteralPath $portLibCrypto)) {
            Write-Verbose "Port libcrypto exists at '$portLibCrypto'"
            $libCrypto = $portLibCrypto
        }
        
        if ($portLibSSL -and (Test-Path -LiteralPath $portLibSSL)) {
            Write-Verbose "Port libssl exists at '$portLibSSL'"
            $libSSL = $portLibSSL
        }
    }

    [PSCustomObject]@{
        LibCrypto = $libCrypto
        LibSSL = $libSSL
    }
}

Function Get-HostInfo {
    <#
    .SYNOPSIS
    Gets the host info that selects the native libraries to install.

    .NOTES
    Currently we support the following C Standard Libraries:
        macOS
        glibc
        musl

    Each support OpenSSL 1.1.x and 3.x and glibc also supports 1.0.x.
    #>
    [CmdletBinding()]
    param ()

    $distribution = Get-Distribution

    switch ($distribution) {
        macOS {
            $libDetails = Get-MacOSOpenSSL

            if ($libDetails.LibCrypto -and $libDetails.LibSSL) {
                $opensslVersion = (Get-OpenSSLInfo -LibSSL $libDetails.LibSSL).Version
                Write-Verbose -Message ("OpenSSL Version: Major {0} Minor {1} Patch {2}" -f (
                    $opensslVersion.Major, $opensslVersion.Minor, $opensslVersion.Build))

                $openssl, $cryptoSource, $sslSource = switch ($opensslVersion) {
                    { $_.Major -eq 1 -and $_.Minor -eq 1 } { '1.1', 'libcrypto.1.1.dylib', 'libssl.1.1.dylib' }
                    { $_.Major -eq 3 } { '3', 'libcrypto.3.dylib', 'libssl.3.dylib' }
                    # Just default to 1.1 in case something catastrophic went wrong
                    default { '1.1', 'libcrypto.1.1.dylib', 'libssl.1.1.dylib' }
                }

                [PSCustomObject]@{
                    Distribution = $distribution
                    StandardLib = 'macOS'
                    OpenSSL = $openssl
                    LibCrypto = @{
                        Source = $cryptoSource
                        Target = $libDetails.LibCrypto
                    }
                    LibSSL = @{
                        Source = $sslSource
                        Target = $libDetails.LibSSL
                    }
                }
            }
        }
        default {
            $opensslVersion = (Get-OpenSSLInfo).Version
            Write-Verbose -Message ("OpenSSL Version: Major {0} Minor {1} Patch {2}" -f (
                $opensslVersion.Major, $opensslVersion.Minor, $opensslVersion.Build))

            $openssl = switch ($opensslVersion) {
                { $_.Major -eq 1 -and $_.Minor -eq 0 } { '1.0' }
                { $_.Major -eq 1 -and $_.Minor -eq 1 } { '1.1' }
                { $_.Major -eq 3 } { '3' }
            }

            $cStd = $null
            try {
                [void][PSWSMan.Native]::gnu_get_libc_version()
                $cStd = 'glibc'
            }
            catch [EntryPointNotFoundException] {
                # gnu_get_libc_version() is GLIBC, we fallback on a check to musl through ldd --version.
                $libcInfo = exec ldd --version
                $libcVerbose = "Not glibc, checking musl with ldd --version:`nSTDOUT: {0}`nSTDERR: {1}`nRC: {2}" -f (
                    $libcInfo.Stdout, $libcInfo.Stderr, $libcInfo.ExitCode)
                Write-Verbose -Message $libcVerbose

                # ldd --version can output on either STDOUT/STDERR so we check both
                if (($libcInfo.Stdout + $libcInfo.Stderr).Contains('musl', 'CurrentCultureIgnoreCase')) {
                    $cStd = 'musl'
                }
            }

            # We don't need to modify the symlinks as the linked SSL libs should already match what's in the PATH.
            # Only exception is CentOS 7 which has libcrypto.so.10 and libssl.so.10.
            # | OpenSSL Version |     crypto name    |     ssl name    |
            # | 1.0.x           | libcrypto.so.1.0.0 | libssl.so.1.0.0 |
            # | 1.1.x           | libcrypto.so.1.1   | libssl.so.1.1   |
            # | 3.x             | libcrypto.so.3     | libssl.so.3     |
            if ($distribution -eq 'centos7') {
                $libCrypto = @{
                    Source = 'libcrypto.so.1.0.0'
                    Target = '/lib64/libcrypto.so.10'
                }
                $libSSL = @{
                    Source = 'libssl.so.1.0.0'
                    Target = '/lib64/libssl.so.10'
                }
            }
            else {
                $libCrypto = $null
                $libSSL = $null
            }

            [PSCustomObject]@{
                Distribution = $distribution
                StandardLib = $cStd
                OpenSSL = $openssl
                LibCrypto = $libCrypto
                LibSSL = $libSSL
            }
        }
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
    or for all checks. The absence of a switch does not disable those checksomi, it only enables the specific check
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
    Deprecated and no longer used.

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

    if ($Distribution) {
        Write-Warning -Message "-Distribution is deprecated and will be removed in a future version"
    }

    $hostInfo = Get-HostInfo

    if (-not $hostInfo.StandardLib -or -not $hostInfo.OpenSSL) {
        $msg = "Failed to select the necessary library, the host isn't macOS, Linux based on GLIBC or musl, or OpenSSL isn't installed"
        Write-Error -Message $msg -Category InvalidOperation
        return
    }

    $library = '{0}-{1}' -f ($hostInfo.StandardLib, $hostInfo.OpenSSL)
    Write-Verbose -Message "Installing WSMan libs for '$library'"

    $pwshDir = Split-Path -Path ([PSObject].Assembly.Location) -Parent
    $distributionLib = Join-Path $Script:LibPath -ChildPath $library
    $libExtension = if ($hostInfo.StandardLib -eq 'macOS') { 'dylib' } else { 'so' }

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

            if (Test-Path -LiteralPath $destPath) {
                Write-Verbose -Message "Creating backup of $($_.Name) to $($_.Name).bak"
                Copy-Item -LiteralPath $destPath -Destination "$($destPath).bak" -Force
            }
            
            Copy-Item -LiteralPath $_.Fullname -Destination $destPath
            $notify = $true
        }
    }

    # These symlinks are either no longer needed or we set them to our own path.
    Get-Item -Path (Join-Path -Path $pwshDir -ChildPath 'lib*.so*') |
        Where-Object { $_.Name -match 'lib(ssl|crypto)\.so.*' } |
        ForEach-Object -Process {
            Write-Verbose -Message "Removing existing symlink '$($_.FullName)'"
            $_ | Remove-Item -Force
        }

    $hostInfo.LibCrypto, $hostInfo.LibSSL | ForEach-Object -Process {
        if (-not $_) {
            return
        }

        $srcPath = Join-Path -Path $pwshDir -ChildPath $_.Source
        $create = $true
        $srcLink = Get-Item -LiteralPath $srcPath -ErrorAction SilentlyContinue
        if ($srcLink) {
            if ($srcLink.Target -ne $_.Target) {
                $srcLink | Remove-Item -Force
            }
            else {
                $create = $false
            }
        }

        if ($create) {
            Write-Verbose -Message "Creating symbolic link '$srcPath' -> '$($_.Target)'"
            New-Item -Path $srcPath -ItemType SymbolicLink -Value $_.Target | Out-Null
        }
    }

    if ($notify) {
        $msg = 'WSMan libs have been installed, please restart your PowerShell session to enable it in PowerShell'
        Write-Warning -Message $msg
    }
}

Function Register-TrustedCertificate {
    <#
    .SYNOPSIS
    Registers a certificate into the system's trusted store.

    .DESCRIPTION
    Registers a certificate, or a chain or certificates, into the trusted store for the current Linux distribution.

    .PARAMETER Name
    The name of the certificate file to use when placing it into the trusted store directory. If not set then the
    value 'PSWSMan-(sha256 hash of certs)' will be used.

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
                # macOS is special, we don't use the builtin LibreSSL setup and rely on brew or port to provide
                # OpenSSL. This means the path to the cert dir could change at any point in the future and we can't
                # rely on default system locations. Instead we determine the path to the libssl.dylib library and use
                # that to PInvoke the OPENSSLDIR value that it has registered. If that fails then fallback to what
                # should be the brew default '/user/local/etc/openssl@1.1/certs'.
                $libSSL = (Get-MacOSOpenSSL).LibSSL

                $opensslPath = Split-Path -Path (Split-Path $libSSL -Parent) -Parent
                $opensslBin = Join-Path -Path $opensslPath -ChildPath bin
                $cRehash = Join-Path -Path $opensslBin -ChildPath c_rehash

                $certDirectory = (Get-OpenSSLInfo -LibSSL $libSSL).SSLDir
                if (-not $certDirectory) {
                    $certDirectory = '/usr/local/etc/openssl@1.1'
                }

                (Join-Path -Path $certDirectory -ChildPath certs), $cRehash
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

        # We create the child dir if it doesn't exist but we want the parent to at least exist
        $parentDir = Split-Path $certPath -Parent
        if (-not (Test-Path -LiteralPath $parentDir)) {
            $msg = "Failed to find the expected cert trust parent dir at '$parentDir' for distribution '$distribution'"
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
                $hashStr = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash
                $Name = "PSWSMan-$hashStr"
            }

            if (-not (Test-Path $certPath)) {
                if ($PSCmdlet.ShouldProcess($certPath, 'Create')) {
                    Write-Verbose -Message "Creating trust cert dir at '$certPath'"
                    New-Item -Path $certPath -ItemType Directory | Out-Null
                }
            }

            $destCertPath = Join-Path -Path $certPath -ChildPath "$Name.$certExtension"
            if ($PSCmdlet.ShouldProcess($destCertPath, 'Register')) {
                Write-Verbose -Message "Creating trust cert file at '$destCertPath'"
                Copy-Item -LiteralPath $tempFile -Destination $destCertPath -Force

                # The file must be executable
                exec chmod 755 $destCertPath | Out-Null

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
