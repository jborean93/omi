# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

$Global:Distribution = 'unknown'
if (Test-Path -LiteralPath /tmp/distro.txt) {
    $Global:Distribution = (Get-Content -LiteralPath /tmp/distro.txt -Raw).Trim()
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
