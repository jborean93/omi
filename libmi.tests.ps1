# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

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
    Import-Module -Name powershell-yaml
    $config = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $PSScriptRoot/integration_environment/inventory.yml -Raw)

    $domain = $config.all.vars.domain_name
    $username = '{0}@{1}' -f ($config.all.vars.domain_username, $domain.ToUpper())
    $password = $config.all.vars.domain_password
    $credential = [PSCredential]::new($username, (ConvertTo-SecureString -AsPlainText -Force -String $password))
    $hostname = '{0}.{1}' -f ([string]$config.all.children.windows.hosts.Keys, $domain)
    $hostnameIP = $config.all.children.windows.hosts.DC01.ansible_host

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
    It "Connects over HTTPS - <Authentication>" -TestCases (
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        $invokeParams = @{
            ComputerName = $hostname
            Credential = $credential
            Authentication = $Authentication
            ScriptBlock = { hostname.exe }
            UseSSL = $true
        }

        # Debian 8 comes with an older version of pwsh that doesn't have New-PSSessionOption
        if ((Get-Command -Name New-PSSessionOption -ErrorAction SilentlyContinue)) {
            $invokeParams.SessionOption = (New-PSSessionOption -SkipCACheck -SkipCNCheck)
        }

        $actual = Invoke-Command @invokeParams
        $actual | Should -Be $hostname.Split('.')[0].ToUpper()
    }

    It "Connects over HTTP with GSSAPI auth - <Authentication>" -TestCases (
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        $invokeParams = @{
            ComputerName = $hostname
            Credential = $credential
            Authentication = $Authentication
            ScriptBlock = { hostname.exe }
        }
        $actual = Invoke-Command @invokeParams
        $actual | Should -Be $hostname.Split('.')[0].ToUpper()
    }

    # CentOS 7 does not have a new enough version of GSSAPI to work with NTLM auth.
    # Debian 8 does not have the gss-ntlmssp package available.
    It "Connects over HTTP with NTLM auth" -Skip:($Global:Distribution -in @('centos7', 'debian8')) {
        $invokeParams = @{
            ComputerName = $hostnameIP
            Credential = $credential
            Authentication = 'Negotiate'
            ScriptBlock = { hostname.exe }
        }
        $actual = Invoke-Command @invokeParams
        $actual | Should -Be $hostname.Split('.')[0].ToUpper()
    }

    It "Connects over HTTP with implicit auth - <Authentication>" -TestCases (
        @{ Authentication = 'Negotiate' },
        @{ Authentication = 'Kerberos' }
    ) {
        $invokeParams = @{
            ComputerName = $hostname
            Authentication = $Authentication
            ScriptBlock = { hostname.exe }
        }

        Invoke-Kinit -Credential $credential

        try {
            $actual = Invoke-Command @invokeParams
            $actual | Should -Be $hostname.Split('.')[0].ToUpper()
        } finally {
            kdestroy
        }
    }
}

Describe "Kerberos delegation" {
    It "Connects with defaults - no delegation" {
        $invokeParams = @{
            ComputerName = $hostname
            Credential = $credential
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
        Invoke-Kinit -Credential $credential -Forwardable

        $invokeParams = @{
            ComputerName = $hostname
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