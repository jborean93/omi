# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

# Setting an env var in .NET doesn't actually change the process env table. For these tests to actually manipulate the
# verification behaviour we need to use PInvoke and call setenv directory.
Add-Type -Namespace OMI -Name Environment -MemberDefinition @'
[DllImport("libc")]
public static extern void setenv(string name, string value);

[DllImport("libc")]
public static extern void unsetenv(string name);
'@

Import-Module -Name powershell-yaml
$Global:Config = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $PSScriptRoot/integration_environment/inventory.yml -Raw)

$domain = $Global:Config.all.vars.domain_name
$username = '{0}@{1}' -f ($Global:Config.all.vars.domain_username, $domain.ToUpper())
$password = $Global:Config.all.vars.domain_password
$hostname = '{0}.{1}' -f ([string]$Global:Config.all.children.windows.hosts.Keys, $domain)
$Global:TestHostInfo = [PSCustomObject]@{  
    Credential = [PSCredential]::new($Username, (ConvertTo-SecureString -AsPlainText -Force -String $Password))
    Hostname = $hostname
    HostnameIP = $Global:Config.all.children.windows.hosts.DC01.ansible_host
    NetbiosName = $hostname.Split('.')[0].ToUpper()
}

$null = (krb5-config --version) -match 'release\s*(.*)'
$Global:KrbVersion = [Version]$Matches[1]

$Global:Distribution = 'unknown'
if (Test-Path -LiteralPath /tmp/distro.txt) {
    $Global:Distribution = (Get-Content -LiteralPath /tmp/distro.txt -Raw).Trim()
}

$Global:ExchangeOnline = $null
$Global:ExchangeOnlineCert = $null
$exchangeMetaPath = [IO.Path]::Combine($PSScriptRoot, 'integration_environment', 'exchange.json')
$exchangeCertPath = [IO.Path]::Combine($PSScriptRoot, 'integration_environment', 'exchange-cert.pfx')

if (Test-Path -LiteralPath $exchangeMetaPath) {
    $Global:ExchangeOnline = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $exchangeMetaPath -Raw)

    if (Test-Path -LiteralPath $exchangeCertPath) {
        $certPass = ConvertTo-SecureString -AsPlainText -Force -String $Global:ExchangeOnline.client_secret
        $Global:ExchangeOnlineCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $exchangeCertPath, $certPass)
    }
}

BeforeAll {
    Function Invoke-Kinit {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)]
            [PSCredential]
            $Credential,

            [Switch]
            $Forwardable
        )

        $kinitArgs = [System.Collections.Generic.List[String]]@()
        if ($Forwardable) {
            $kinitArgs.Add('-f')
        }
        $kinitArgs.Add($Credential.UserName)

        $null = $Credential.GetNetworkCredential().Password | kinit $kinitArgs
    }

    Function Get-EXOCredential {
        [CmdletBinding(DefaultParameterSetName='ClientSecret')]
        param (
            [Parameter(Mandatory=$true)]
            [String]
            $TenantID,

            [Parameter(Mandatory=$true)]
            [String]
            $ClientID,

            [Parameter(Mandatory=$true, ParameterSetName='ClientSecret')]
            [Alias('Credential')]
            [SecureString]
            $ClientSecret,

            [Parameter(Mandatory=$true, ParameterSetName='Certificate')]
            [System.Security.Cryptography.X509Certificates.X509Certificate2]
            $Certificate
        )

        Import-Module -Name MSAL.PS -ErrorAction Stop

        $msalParams = @{
            TenantID = $TenantID
            ClientID = $ClientID
            Scopes = 'https://outlook.office365.com/.default'
        }

        # Build the client credential based on the auth type chosen.
        if ($Certificate) {
            $msalParams.ClientCertificate = $Certificate
        } else {
            $msalParams.ClientSecret = $ClientSecret
        }

        $msalResult = Get-MsalToken @msalParams

        # EXO uses Basic auth that wraps the actual MSAL token. It is in the form
        # Base64("OAuthUser@$TenantID:Bearer $MSALToken")
        $bearerToken = ConvertTo-SecureString -AsPlainText -Force -String "Bearer $($msalResult.AccessToken)"
        [PSCredential]::new("OAuthUser@$TenantID", $bearerToken)
    }
}

Describe "Checking the compiled library's integrity" {
    It "Exposes the custom public version function" {
        $version = &"$PSScriptRoot/tools/Get-OmiVersion.ps1"

        # All versions we produce should have a major version that's 1 or more
        # The minor versions can be anything so we can't really check those
        $version | Should -BeOfType System.Version
        $version.Major | Should -BeGreaterThan 0
    }
}

Describe "PSRemoting through WSMan" {
    It "Connects over HTTP with GSSAPI auth - <Authentication>" -TestCases (
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        $invokeParams = @{
            ComputerName = $Global:TestHostInfo.Hostname
            Credential = $Global:TestHostInfo.Credential
            Authentication = $Authentication
            ScriptBlock = { hostname.exe }
        }
        $actual = Invoke-Command @invokeParams
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    # CentOS 7 does not have a new enough version of GSSAPI to work with NTLM auth.
    # Debian 8 does not have the gss-ntlmssp package available.
    It "Connects over HTTP with NTLM auth" -Skip:($Global:Distribution -in @('centos7', 'debian8')) {
        $invokeParams = @{
            ComputerName = $Global:TestHostInfo.HostnameIP
            Credential = $Global:TestHostInfo.Credential
            Authentication = 'Negotiate'
            ScriptBlock = { hostname.exe }
        }
        $actual = Invoke-Command @invokeParams
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Connects over HTTP with implicit auth - <Authentication>" -TestCases (
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        $invokeParams = @{
            ComputerName = $Global:TestHostInfo.Hostname
            Authentication = $Authentication
            ScriptBlock = { hostname.exe }
        }

        Invoke-Kinit -Credential $Global:TestHostInfo.Credential

        try {
            $actual = Invoke-Command @invokeParams
            $actual | Should -Be $Global:TestHostInfo.NetbiosName
        } finally {
            kdestroy
        }
    }
}

Describe "PSRemoting over HTTPS" {
    # We first need to discover the actual HTTPS endpoints we've set up for the channel binding and cert verification
    # tests
    $getCertParams = @{
        ComputerName = $Global:TestHostInfo.Hostname
        Credential = $Global:TestHostInfo.Credential
        Authentication = 'Negotiate'
    }
    $Global:CertInfo = Invoke-Command @getCertParams -ScriptBlock {
        Get-ChildItem -LiteralPath Cert:\LocalMachine\My |
            Where-Object { $_.FriendlyName.StartsWith('test_') } |
            ForEach-Object -Process {
                $dummy, $testName, $port = $_.FriendlyName -split '_', 3
                [PSCustomObject]@{
                    Name = $testName
                    Port = $port
                }
            }
    } | Select-Object -Property Name, Port

    BeforeEach {
        $GoodCertPort = ($Global:CertInfo | Where-Object Name -eq 'verification').Port
        $BadCAPort = ($Global:CertInfo | Where-Object Name -eq 'verification-bad-ca').Port
        $BadCNPort = ($Global:CertInfo | Where-Object Name -eq 'verification-bad-cn').Port
        $ExplicitCertPort = ($Global:CertInfo | Where-Object Name -eq 'verification-other-ca').Port

        $CommonInvokeParams = @{
            ComputerName = $Global:TestHostInfo.Hostname
            Credential = $Global:TestHostInfo.Credential
            ScriptBlock = { hostname.exe }
            UseSSL = $true
        }
        # Debian 8 comes with an older version of pwsh that doesn't have New-PSSessionOption
        if ((Get-Command -Name New-PSSessionOption -ErrorAction SilentlyContinue)) {
            $CommonInvokeParams.SessionOption = (New-PSSessionOption -SkipCACheck -SkipCNCheck)
        }

        [OMI.Environment]::unsetenv('OMI_SKIP_CA_CHECK')
        [OMI.Environment]::unsetenv('OMI_SKIP_CN_CHECK')
        [OMI.Environment]::unsetenv('SSL_CERT_FILE')
    }

    AfterEach {
        [OMI.Environment]::unsetenv('OMI_SKIP_CA_CHECK')
        [OMI.Environment]::unsetenv('OMI_SKIP_CN_CHECK')
        [OMI.Environment]::unsetenv('SSL_CERT_FILE')
    }

    # ChannelBindingToken doesn't work on SPNEGO with MIT krb5 until after 1.18.2. Fedora 32 seems to have backported
    # further changes into the package which reports 1.18.2 but in reality has the fix so we also check that.
    It "Connects over HTTPS - Negotiate" -Skip:('fedora32' -ne $Global:Distribution -and $Global:KrbVersion -lt [Version]'1.18.3') {
        $actual = Invoke-Command @CommonInvokeParams -Port $GoodCertPort -Authentication Negotiate
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Connects over HTTPS with NTLM auth" -Skip:('fedora32' -ne $Global:Distribution -and $Global:KrbVersion -lt [Version]'1.18.3') {
        # Using an IP address means we break Kerberos auth and fallback to NTLM
        $invokeParams = $CommonInvokeParams.Clone()
        $invokeParams.ComputerName = $Global:TestHostInfo.HostnameIP

        [OMI.Environment]::setenv('OMI_SKIP_CN_CHECK', '1')
        $actual = Invoke-Command @invokeParams -Port $GoodCertPort -Authentication Negotiate
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Connects over HTTPS - Kerberos" {
        $actual = Invoke-Command @CommonInvokeParams -Port $GoodCertPort -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Trusts a certificate using the SSL_CERT_FILE env var" {
        [OMI.Environment]::setenv('SSL_CERT_FILE',
            [IO.Path]::Combine($PSScriptRoot, 'integration_environment', 'cert_setup', 'ca_explicit.pem'))
        $actual = Invoke-Command @CommonInvokeParams -Port $ExplicitCertPort -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    $cbtInfo = $Global:CertInfo | Where-Object Name -Like 'cbt-*' | ForEach-Object {
        @{ Name = $_.Name; Port = $_.Port }  # TestCases takes a Hashtable not a PSCustomObject
    }
    It "ChannelBindingToken works with certficate - <Name>" -TestCases $cbtInfo {
        # Debian 10 seems to fail to verify certs signed with SHA-1, just skip in that case
        if ('debian10' -eq $Global:Distribution -and $Name -eq 'cbt-sha1') {
            return
        }
        $actual = Invoke-Command @CommonInvokeParams -Port $Port -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    # Debian 8 ships with a really old version of OpenSSL that does not offer CN verification.
    $skipCN = 'debian8' -eq $Global:Distribution
    It "Fails to verify the CN - <Scenario>" -Skip:$skipCN -TestCases @(
        @{
            Scenario = 'Default'
            EnvVars = @{}
            Expected = '*certificate verify failed*'
        },
        @{
            Scenario = 'Skip CA check'
            EnvVars = @{ OMI_SKIP_CA_CHECK =  '1' }
            Expected = '*Certificate hostname verification failed - set OMI_SKIP_CN_CHECK=1 to ignore.*'
        },
        @{
            Scenario = 'OMI_SKIP_CN_CHECK=0'
            EnvVars = @{ OMI_SKIP_CN_CHECK = '0' }
            Expected = '*certificate verify failed*'
        }
        @{
            Scenario = 'OMI_SKIP_CN_CHECK=false'
            EnvVars = @{ OMI_SKIP_CN_CHECK = 'fAlse' }
            Expected = '*certificate verify failed*'
        }
    ) {
        foreach ($kvp in $EnvVars.GetEnumerator()) {
            [OMI.Environment]::setenv($kvp.Key, $kvp.Value)
        }
        { Invoke-Command @CommonInvokeParams -Port $BadCNPort -Authentication Kerberos } | Should -Throw $Expected
    }

    It "Ignores a CN failure with env value '<Value>'" -TestCases @(
        @{ Value = '1' },
        @{ Value = 'trUe' }
    ) -Skip:$skipCN {
        [OMI.Environment]::setenv('OMI_SKIP_CN_CHECK', $Value)
        $actual = Invoke-Command @CommonInvokeParams -Port $BadCNPort -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Fails to verify the CA - <Scenario>" -TestCases @(
        @{
            Scenario = 'Default'
            EnvVars = @{}
        },
        @{
            Scenario = 'Skip CN check'
            EnvVars = @{ OMI_SKIP_CN_CHECK =  '1' }
        },
        @{
            Scenario = 'OMI_SKIP_CA_CHECK=0'
            EnvVars = @{ OMI_SKIP_CA_CHECK = '0' }
        }
        @{
            Scenario = 'OMI_SKIP_CA_CHECK=false'
            EnvVars = @{ OMI_SKIP_CA_CHECK = 'faLse' }
        }
    ) {
        foreach ($kvp in $EnvVars.GetEnumerator()) {
            [OMI.Environment]::setenv($kvp.Key, $kvp.Value)
        }
        { Invoke-Command @CommonInvokeParams -Port $BadCAPort -Authentication Kerberos } | Should -Throw '*certificate verify failed*'
    }

    It "Ignores a CA failure with env value '<Value>'" -TestCases @(
        @{ Value = '1' },
        @{ Value = 'truE' }
    ) {
        [OMI.Environment]::setenv('OMI_SKIP_CA_CHECK', $Value)
        $actual = Invoke-Command @CommonInvokeParams -Port $BadCAPort -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }

    It "Failed to verify the CA and CN - <Scenario>" -Skip:$skipCN -TestCases @(
        @{
            Scenario = 'No skips'
            EnvVars = @{}
            Expected = '*certificate verify failed*'
        },
        @{
            Scenario = 'Skip CA check'
            EnvVars = @{ OMI_SKIP_CA_CHECK = '1' }
            Expected = '*Certificate hostname verification failed - set OMI_SKIP_CN_CHECK=1 to ignore.*'
        },
        @{
            Scenario = 'Skip CN check'
            EnvVars = @{ OMI_SKIP_CN_CHECK = '1' }
            Expected = '*certificate verify failed*'
        }
    ) {
        foreach ($kvp in $EnvVars.GetEnumerator()) {
            [OMI.Environment]::setenv($kvp.Key, $kvp.Value)
        }
        { Invoke-Command @CommonInvokeParams -Port 5986 -Authentication Kerberos } | Should -Throw $Expected
    }

    It "Ignores a CA and CN failure" {
        [OMI.Environment]::setenv('OMI_SKIP_CA_CHECK', '1')
        [OMI.Environment]::setenv('OMI_SKIP_CN_CHECK', '1')
        $actual = Invoke-Command @CommonInvokeParams -Port 5986 -Authentication Kerberos
        $actual | Should -Be $Global:TestHostInfo.NetbiosName
    }
}

Describe "Kerberos delegation" {
    It "Connects with defaults - no delegation" {
        $invokeParams = @{
            ComputerName = $Global:TestHostInfo.Hostname
            Credential = $Global:TestHostInfo.Credential
            Authentication = 'Negotiate'
            ScriptBlock = { klist.exe }
        }
        $actual = Invoke-Command @invokeParams
        $actual = $actual -join "`n"

        $actual | Should -Not -BeLike "*forwarded*"
    }

    It "Connects with implicit forwardable ticket - <Authentication>" -TestCases @(
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        Invoke-Kinit -Credential $Global:TestHostInfo.Credential -Forwardable

        $invokeParams = @{
            ComputerName = $Global:TestHostInfo.Hostname
            Authentication = $Authentication
            ScriptBlock = { klist.exe }
        }
        try {
            $actual = Invoke-Command @invokeParams
        } finally {
            kdestroy
        }

        $actual = $actual -join "`n"
        $actual | Should -BeLike "*forwarded*"
    }
}

Describe "Exchange Online" -Skip:(-not $Global:ExchangeOnline) {
    It "Connects using a client secret" {
        $credentialParams = @{
            TenantID = $Global:ExchangeOnline.tenant_id
            ClientID = $Global:ExchangeOnline.client_id
            ClientSecret = (ConvertTo-SecureString -AsPlainText -Force -String $Global:ExchangeOnline.client_secret)
        }
        $cred = Get-EXOCredential @credentialParams

        $sessionParams = @{
            Authentication = 'Basic'
            ConfigurationName = 'Microsoft.Exchange'
            ConnectionUri = 'https://outlook.office365.com/PowerShell-LiveId?BasicAuthToOAuthConversion=true'
            Credential = $cred
            AllowRedirection = $true
        }
        $session = New-PSSession @sessionparams
        $session | Should -Not -BeNullOrEmpty

        $proxyModule = Import-PSSession -Session $session -DisableNameChecking
        $proxyModule | Should -Not -BeNullOrEmpty

        $session | Remove-PSSession
    }

    It "Connects using a certificate" -Skip:(-not $Global:ExchangeOnlineCert) {
        $credentialParams = @{
            TenantID = $Global:ExchangeOnline.tenant_id
            ClientID = $Global:ExchangeOnline.client_id
            Certificate = $Global:ExchangeOnlineCert
        }
        $cred = Get-EXOCredential @credentialParams

        $sessionParams = @{
            Authentication = 'Basic'
            ConfigurationName = 'Microsoft.Exchange'
            ConnectionUri = 'https://outlook.office365.com/PowerShell-LiveId?BasicAuthToOAuthConversion=true'
            Credential = $cred
            AllowRedirection = $true
        }
        $session = New-PSSession @sessionparams
        $session | Should -Not -BeNullOrEmpty

        $proxyModule = Import-PSSession -Session $session -DisableNameChecking
        $proxyModule | Should -Not -BeNullOrEmpty

        $session | Remove-PSSession
    }
}