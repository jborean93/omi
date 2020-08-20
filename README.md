# Open Management Infrastructure - PowerShell Edition

[![Build Status](https://dev.azure.com/jborean93/jborean93/_apis/build/status/jborean93.omi?branchName=main)](https://dev.azure.com/jborean93/jborean93/_build/latest?definitionId=6&branchName=main)

This is a fork of Microsoft [OMI](https://github.com/microsoft/omi) repository.

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

I am not looking at fixing any underlying problems in this library or work on the server side part of OMI.
This is purely focusing on improving the experience when using WinRM as a client on non-Windows based hosts within PowerShell.
There are no guarantees of support, you are free to change whatever you wish on your own builds but use the code here at your own risk.

## Build

This repo tries to make it simple to build your own copy of `libmi` of the distribution of choice.
The actual upstream OMI releases are based on a "universal" Linux build but I've just setup a script that will build a library for each distribution.
To start a build run `./build.py {distribution}`, if not distribution was supplied the script will prompt you to select one from a list.
There are some other arguments you can supply to alter the behaviour of the build script like:

+ `--debug`: Generate a debug build of the library
+ `--docker`: Build the library in a Docker container without polluting your current environment
+ `--output-script`: Whether to output the build bash script instead of running it
+ `--prefix`: Set the OMI install prefix path (default: `/opt/omi`). This is only useful for defining a custom config base path that the library will use
+ `--skip-clear`: Don't clear the `Unix/build-{distribution}` folder before building to speed up compilation after making changes to the code
+ `--skip-deps`: Don't install the required build dependencies

The aim is to support the same distributions that PowerShell supports but so far the build tool only supports a limited number of distributions.
The distributions that are currently setup in the `build.py` script are:

+ [centos7.json](distribution_meta/centos7.json)
+ [centos8.json](distribution_meta/centos8.json)
+ [debian8.json](distribution_meta/debian8.json)
+ [debian9.json](distribution_meta/debian9.json)
+ [debian10.json](distribution_meta/debian10.json)
+ [fedora31.json](distribution_meta/fedora31.json)
+ [fedora32.json](distribution_meta/fedora32.json)
+ [macOS.json](distribution_meta/macOS.json) - Cannot be built on a Docker container, must be built on an actual macOS host
+ [ubuntu16.04.json](distribution_meta/ubuntu16.04.json)
+ [ubuntu18.04.json](distribution_meta/ubuntu18.04.json)

The json file contains the system packages that are required to compile OMI under the `build_deps` key.

If your distribution isn't listed here or you just wish to compile the code manually this is what the build script essentially does:

```bash
# Install all the deps required by OMI

cd Unix
./configure --outputdirname=build-distribution --prefix=/opt/omi
make
```

Once finished it will generate a whole bunch of libraries required by OMI but the one we are interested in is in `Unix/build-{distribution}/lib/libmi.so`.
You can then use `libmi.so` with PowerShell to enhance your WSMan experience on Linux.

## Installing

Once build, simply copy the `libmi` library from `Unix/build-{distribution}/lib` into the PowerShell directory.
The PowerShell directory differs based on each distribution or how it was installed.
An easy way to determine this directory is by running `dirname "$( readlink "$( which pwsh )" )"`

To enable Kerberos authentication you will need to ensure you install the Kerberos system packages that can vary between distros.
See the `.json` files in [distribution_meta](distribution_meta) to see the `test_deps` that are required to test PowerShell with Kerberos auth.
NTLM auth also requires the [gss-ntlmssp](https://github.com/gssapi/gss-ntlmssp) package which is another separate package that can be installed.
This is also documented in the `.json` files for each distribution.

A few thing to note when using the WSMan transport in PowerShell

+ You always need to provide an explicit credential, no implicit auth is current available
  + I'm hoping to add support for using a cred from the Kerberos cache in the future
+ When wanting to use Kerberos auth you need to specify the user in the UPN format, e.g. `username@DOMAIN.COM`. Do not use the Netlogon form `DOMAIN\username`
+ If you want to use Negotiate/Kerberos auth you must also supply `-Authentication Negotiate` or `-Authentication Kerberos` to the cmdlet that uses WSMan
+ When using Basic auth you MUST connect over HTTPS and skip cert verification by adding `-SessionOption (New-PSSession -SkipCACheck -SkipCNCheck)`

## Testing

The [integration_environment](integration_environment) folder has a Vagrant/Ansible setup that will build 2 hosts for integration tests

+ DC01 - Windows domain controller
+ DEBIAN10 - A Linux test host with Docker and the local `omi` repo copied to `~/omi`

To create this environment, run the following:

```bash
cd integration_environment
vagrant up
ansible-playbook main.yml -vv

# To setup the host with pre-built variable from an Azure DevOps CI run, add '-e build_id=<build id>' for that run
ansible-playbook main.yml -vv -e build_id=123
```

The `build_id` variable can be set to any build number from [Azure DevOps jborean93.omi](https://dev.azure.com/jborean93/jborean93/_build?definitionId=6&_a=summary).
When set, the playbook will download the `libmi` library for each distribution from that run for testing.
If you don't specify the `build_id` it will just copy across whatever libraries are located at `Unix/build-{distribution}/lib` to the Debian host.

You can also specify the following `--tags` to only run a specific component of the `main.yml` playbook:

+ `windows`: Setup the Windows domain controller
+ `linux`: Setup the Debian host
+ `build_artifacts`: Run the Azure DevOps libmi download tasks, `-e build_id=` must also be set

The domain information and credentials are dependent on the values in [integration_environment/inventory.yml](integration_environment/inventory.yml).
It defaults to a domain called `omi.test` with the test user `omi@OMI.TEST` with the password `Password01`.
The environment comes prebuilt to allow you to run the [libmi.tests.ps1](libmi.tests.ps1) [Pester](https://github.com/pester/Pester) tests in various distribution Docker containers.
To run tests for all the distributions run the following:

```bash
cd integration_environment
ansible-playbook test.yml -vv

# Run the tests for only 1 distribution, add '-e distribution=<distribution>'
ansible-playbook test.yml -vv -e distribution=centos8
```

If you wish to run more tests manually in the test environment you can log onto the `DEBIAN10` host and start up your own test container with:

```bash
cd integration_environment
vagrant ssh DEBIAN10

cd ~/omi
./test.py --docker --interactive  # Can specify your distribution using a positional arg
```

This will spin up the test environment for you with all the deps and `libmi.so` library installed.
From there you can start up `pwsh` and run whatever you desire.

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

### Can't Fix

+ Cannot do basic auth over HTTP
  + PowerShell hardcodes a check that stops you from doing this for security reasons
  + Really why would you want to do this anyway
+ No certificate validation is done on a HTTPS connection
  + PowerShell hardcodes a check that forces you to do `-UseSSL -SessionOption (New-PSSession -SkipCACheck -SkipCNCheck)`
  + Even if cert validation was added we cannot change the behaviour on PowerShell
+ Cannot add CredSSP authentication
  + Could technically implement the auth code in this library but that won't be easy
  + Cannot bypass the hardcoded check in PowerShell that causes a failure when `-Authentication CredSSP`
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

+ Continue to add more distributions for building/testing
  + Alpine 3.9
  + Alpine 3.10
  + Archlinux
  + OpenSUSE 42.3
  + OpenSUSE Leap 15
+ Add a way to specify the `omicli.conf` file through an env var instead of the hardcoded location
+ Try and find a better way to enable NTLM auth for macOS, current implementation is a bit of hack
+ Add a force NTLM auth to be used in conjunction with `-Authentication Negotiate`
+ Look at creating a "universal" build that OMI does in their normal releases
