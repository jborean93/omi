@{
    ModuleVersion = '2.3.0'
    RootModule = 'PSWSMan'
    GUID = '92ec96bf-3ff4-41b2-8694-cd3ee636d3fd'
    Author = 'Jordan Borean'
    Copyright = 'Copyright (c) 2020 by Jordan Borean'
    Description = "Module to install and manage the forked WSMan client libraries for Linux and macOS.`nSee https://github.com/jborean93/omi for more details."
    PowerShellVersion = '7.0'
    CompatiblePSEditions = 'Core'
    CmdletsToExport = @(
        'Disable-WSManCertVerification',
        'Enable-WSManCertVerification',
        'Get-WSManVersion'
    )
    FunctionsToExport = @(
        'Install-WSMan',
        'Register-TrustedCertificate'
    )
    PrivateData = @{
        PSData = @{
            Tags = @(
                'PSEdition_Core',
                'Linux',
                'MacOS',
                'WSMan',
                'WinRM'
            )
            LicenseUri = 'https://github.com/jborean93/omi/blob/master/LICENSE'
            ProjectUri = 'https://github.com/jborean93/omi'
            ReleaseNotes = 'See https://github.com/jborean93/omi/blob/master/CHANGELOG.md'
            Prerelease = 'dev'
        }
    }
}
