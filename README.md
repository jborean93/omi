# Open Management Infrastructure - PowerShell Edition

[![Build Status](https://dev.azure.com/jborean93/jborean93/_apis/build/status/jborean93.omi?branchName=main)](https://dev.azure.com/jborean93/jborean93/_build/latest?definitionId=6&branchName=main)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSWSMan.svg)](https://www.powershellgallery.com/packages/PSWSMan)

This is a fork of Microsoft [OMI](https://github.com/microsoft/omi) repository.
Read more about this fork in my blog post [Wacky WSMan on Linux](https://www.bloggingforlogging.com/2020/08/21/wacky-wsman-on-linux/).

## Changes from Upstream OMI

The main goal of this fork is to produce an alternative build of `libmi` that is used by PowerShell for WinRM based PSRemoting.
This alternative build is designed to fix the current problems with the shipped version of `libmi`.
Unfortunately there is no interest in upstream to accept any patches for this use case so I've decided to store them in this fork and produce my own builds.
The following changes have been made:

+ Create a compiled build against a newer version of OpenSSL (1.1.x) for distros that include this version
+ Fixed the compiler to work on newer distributions that now have stricter defaults
  + Upstream failed on macOS due to the code using system defined macros
  + Upstream failed on newer `gcc` versions that had stricter default set
+ Fixed up the GSSAPI implementation to work properly
  + macOS works with Kerberos out of the box as the correct symbols and workflow is being used
  + Technically NTLM auth on macOS can work but only does when running over HTTPS. This is due to a fundamental problem with macOS and NTLM when it's wrapped in SPNEGO
  + Ensure the mech set favours Kerberos and only fallsback to NTLM if Kerberos fails
  + Added the `GSS_C_DELEG_POLICY_FLAG` flag to support credential delegation with Kerberos
  + Use `GSS_C_NT_HOSTBASED_SERVICE` with the service `http@<hostname>` principal which works in more situations than before
  + Don't try and resolve the hostname when building the SPN, this goes against the guidelines of GSSAPI, if that behaviour is desired then set it in your `krb5.conf`
  + Commented out unused GSSAPI symbols to improve compatibility on versions that don't have those symbols available
+ Added support for using implicit Kerberos credentials retrieved with `kinit`
  + Will work when both `-Authentication Negotiate` or `-Authentication Kerberos` but the former will only work with Kerberos with no NTLM fallback
  + Should technically require `-Authentication NegotiateWithImplicitCredential` but PowerShell does not pass in the required flags to know this
+ Rewrote the message decryptor used when HTTP message encryption was used over Negotiate or Kerberos auth
  + This now works in more situations whereas before it would fail with an unhelpful `MI_RESULT_FAILED` error
  + Also works against an on-prem Exchange remoting endpoint due to the unique nature of how that encrypted the message
+ Added additional log entries to make debugging slightly easier than before
  + See [logging](#logging) for more details
+ Increased the password length limit to 8KiB to support modern authentication required by O365 WSMan connections
  + The original limit was 1KiB and I've seen JWT tokens that modern auth in O365 exceed 1.5KiB
  + I've set it to 8KiB as that seems to be a common default of HTTP header sizes, if it does exceed that then the server would return a 413 anyway
+ Added support for sending the channel binding tokens when using GSSAPI on a HTTPS connection
  + This will allow the client to authenticate when the WSMan service has set `Auth/CbtHardeningLevel = Strict`
  + If the client fails to derive the CBT token, further information can be found in the [logs](#troubleshooting)
+ Turned on HTTPS certificate verification by default
  + Any HTTPS connections will have OpenSSL check the server's certificate like a proper HTTPS connection
  + For PowerShell versions older than `7.2`, you still need to tell PowerShell to skip the checks but those skip options are ignored in OMI
  + See [https_validation](docs/https_validation.md) for more details on this topic
+ Also create a slightly customised [libpsrpclient](https://github.com/PowerShell/psl-omi-provider)
  + This enables WSMan on distributions that Microsoft does not include `libpsrpclient` for
  + Also allows this fork to fix things that are outside of the OMI codebase

I am not looking at fixing any underlying problems in this library or work on the server side part of OMI.
This is purely focusing on improving the experience when using WinRM as a client on non-Windows based hosts within PowerShell.
There are no guarantees of support, you are free to change whatever you wish on your own builds but use the code here at your own risk.

## Build

See [build](docs/build.md) for more information on how to manually build these libraries.

## Installing

Since the `2.0.0` release there is now a PowerShell module that can be used to install this library on known distributions.
You can see this package at [PSGallery PSWSMan](https://www.powershellgallery.com/packages/PSWSMan/).
To install the WSMan libs through this module you can run the following in PowerShell:

```powershell
Install-Module -Name PSWSMan

# Requires root access to install, Install-WSMan can be run directly if already running as root
sudo pwsh -Command 'Install-WSMan'
```

If you wish to build your own changes you can manually build the module.
Make sure to run this step after you've manually built OMI into the `build/lib` directory.

```bash
./build.py module
```

Once built you can import the module and install the WSMan components.

```powershell
# Import PSWSMan from the repo source, that will source the libs from PSWSMan/lib/{distribution} of the repo
Import-Module -Name ./build/PSWSMan
Install-WSMan
```

You can also manually install the libraries by copying the files `build/lib/{distribution}/lib*` into the PowerShell directory.
The location of the PowerShell directory differs based on each distribution or how it was installed.
An easy way to determine this directory is by running `dirname "$( readlink "$( which pwsh )" )"`

To enable Kerberos authentication you will need to ensure you install the Kerberos system packages that can vary between distros.
See the `.json` files in [distribution_meta](distribution_meta) to see the `test_deps` that are required to test PowerShell with Kerberos auth.
NTLM auth also requires the [gss-ntlmssp](https://github.com/gssapi/gss-ntlmssp) package which is another separate package that can be installed.
This is also documented in the `.json` files for each distribution.

A few thing to note when using the WSMan transport in PowerShell

+ When wanting to use Kerberos auth you need to specify the user in the UPN format, e.g. `username@DOMAIN.COM`. Do not use the Netlogon form `DOMAIN\username`
+ When using Basic auth you MUST connect over HTTPS and skip cert verification by adding `-SessionOption (New-PSSession -SkipCACheck -SkipCNCheck)`
  + While this tells PowerShell to skip the certificate checks, this library will still continue to do so
  + See [https_validation](docs/https_validation.md) for more details on this topic

## Testing

See [testing](docs/testing.md) for more information on how to test the changes here.

## Troubleshooting

There are a few steps you can follow to troubleshoot any problems when using this library in PowerShell.
Most problems are split into 3 different categories:

+ [Loading the library](#library-errors)
+ [Authentication failures](#authentication-failures)
+ [WSMan errors](#wsman-errors)

The `libmi` library also has a builtin logging mechanism that you can enable to help with debugging issues at runtime.
To enable logging for OMI you first need to create a file at `/opt/omi/etc/omicli.conf` with the following contents:

```text
# Can be ERROR, WARNING, INFO, DEBUG, VERBOSE (requires a debug build) with the default being WARNING
# Any previous values will also be set, i.e. setting INFO will enable ERROR and WARNING
loglevel = DEBUG

# The directory (must end with /) to place the log file in
logpath = /tmp/

# The name of the logfile to write to
logfile = omi-pwsh.log
```

If you have specified a custom `--prefix` path when you built `libmi`, then `/opt/omi` should be subsituted with the prefix you specified.
You may also want to create the dir `/opt/omi/var/log` as this directory is used to place the HTTP trace files.

### Library Errors

If PowerShell fails to load the `libpsrpclient` or `libmi` library it can fail with the error

> This parameter set requires WSMan, and no supported WSMan client library was found. WSMan is either not installed or unavailable for this system.

The main thing you can do to test this out is to very the linked libraries are present on the system.
Run the following to get information on all the linked libraries

```bash
PWSHDIR="$( dirname "$( readlink "$( which pwsh )" )" )"

# On Linux
ldd "${PWSHDIR}/libpsrpclient.so"
ldd "${PWSHDIR}/libmi.so"

# On macOS
otool -L "${PWSHDIR}/libpsrpclient.dylib"
otool -L "${PWSHDIR}/libmi.dylib"
```

Read through this list and make sure each of the libraries it reference actually resolve to a path on the system.
There may be a chance that you never replaced the original `libmi` library with one from this fork.

### Authentication Failures

Authentication can be a tricky thing to debug due to the complexities of GSSAPI on Linux.
If you would like to use Kerberos authentication (you should) then the first time you should verify is that you are able to get a Kerberos ticket for your user.
You can test this by running `kinit username@DOMAIN.COM` and entering your password.
If this fails then you have a system setup issue with your Kerberos config and should fix that first.
Once you have verified the system can talk to the domain controller then you can start testing using it in PowerShell.
A few things you should be aware of when it comes to Kerberos authentication:

+ Make sure you are connecting to the host with its fully qualified domain name
  + Kerberos is highly dependent on DNS working and uses the FQDN of the host to verify its info in the domain controller
+ Make sure the time on the PowerShell host and the remote host are in sync
+ If passing in an explicit credential, make sure you use the UPN form `username@DOMAIN.COM`

A helpful way to troubleshoot Kerberos issues is to set the env var `KRB5_TRACE=/dev/stdout` before opening PowerShell.
This will output any any GSSAPI events to the console allowing you to see the steps it follows and potentially trace down the underlying problem in your scenario.

NTLM authentication is less picky about the environment it is run in but it comes at the downside of it being less secure.
NTLM auth works out of the box on macOS but on other Linux hosts you need to ensure you have installed the [gss-ntlmssp](https://github.com/gssapi/gss-ntlmssp) package.
Have a look through the [distribution_meta](distribution_meta) `.json` files to see what name this package comes under for your distribution.

### WSMan errors

These are the hardest problems to debug as it's usually a sign of a logic issue in the `libmi` code.
The best advice I can give you here is to create a debug build of the library using `./build.py --debug` and make sure you have enable the `VERBOSE` level logs in the `omicli.conf` file.
Hopefully the logs can at least narrow down where the problem lies.

## Known Issues

There are a few known issues so far that are split into the can and can't fix categories.
Can fix issues are ones that are problems in this codebase that can be fixed and a new library recompiled.
Can't fix issues are either issues that would take a lot of effort to implement and/or require changes in other libraries which is out of scope here.

### Can Fix

+ HTTP trace files containing the HTTP payloads sent in an exchange are placed in `{prefix}/var/log` if that folder exists
  + These trace files should only be created if the `loglevel` in the `omicli.conf` file is set to `DEBUG` or higher but currently that does not happen
+ No CredSSP authentication
  + Implementing CredSSP authentication is quite complex but is theoretically possible

### Can't Fix

+ Cannot do basic auth over HTTP
  + PowerShell hardcodes a check that stops you from doing this for security reasons
  + Really why would you want to do this anyway
+ When using MIT krb5 as the GSSAPI backend, Kerberos delegation will only work when `/etc/krb5.conf` contains `[libdefaults]\nforwardable = true`
  + This is a problem in that library where `gss_acquire_cred_with_pass` will only acquire a forwardable ticket (required for delegation) if the `krb5.conf` contains the `forwardable = true` setting
  + Recent versions of Heimdal are not affected
  + You can run `kinit -f username@DOMAIN.COM` to get a forwardable ticket regardless of the `krb5.conf` value and use the implicit credential instead

## Contributing

I'm happy to look at any PRs or help with any issues but bear in mind that this is something I work on in my spare time.
There is no guarantee that I will be able to solve your problems or look at a PR.
If you are making any changes to the code in `Unix/` then I recommend you add a comment `# JBOREAN CHANGE: reason for change`.
This allows me to easily merge any upstream changes and compare what has been edited here and why compared to any incoming changes.

## Backlog

See [Can Fix](#cant-fix) for known bugs that can be fixed.
Otherwise other features/changes that are in the backlog are:

+ Add a way to specify the `omicli.conf` file through an env var instead of the hardcoded location
+ Try and find a better way to enable NTLM auth for macOS, current implementation is a bit of hack
+ Add a force NTLM auth to be used in conjunction with `-Authentication Negotiate`
