# Open Management Infrastructure - PowerShell Edition

This is a fork of Microsoft [OMI](https://github.com/microsoft/omi) repository.


## Goals

The main goal of this fork is to produce an alternative build of `libmi` that is used by PowerShell for WinRM based
PSRemoting. This alternative build will be designed to fix current problems with the shipped version of `libmi` such
as:

+ Being compiled against a newer version of OpenSSL (1.1.x)
+ Enable both Kerberos and NTLM auth on all non-Windows hosts, not just ones with MIT KRB5

I am not looking at fixing any underlying problems in this library or work on the server side part of OMI. This is
purely focusing on improving the experience when using WinRM as a client on non-Windows based hosts.

## TODO

+ Document the steps required to build OMI on each distro
+ Try and find a better way to enable NTLM auth for macOS, current implementation is a bit of hack
+ Add the `GSS_C_DELEG_POLICY_FLAG` when setting up the GSSAPI context to enable Kerberos delegation
+ Create scripts to automatically build the binaries for popular distributions that can run PowerShell
+ Look at setting up some integration tests, either in CI or through manual runs
+ See if there is a better way of reporting errors for easier debugging when using PowerShell
