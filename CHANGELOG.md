# Changelog

This is the changelog for this fork of OMI.
It documents the changes in each of the tagged releases

## 2.0.0 - TBD

### Breaking Changes

+ GitHub release artifacts are now a `.tar.gz` for each distribution containing `libmi` and `libpsrp`
+ Removed the script `tools/Get-OmiVersion.ps1` in favour of `Get-WSManVersion` that is included in the new `PSWSMan` module

### Changes

+ Created `PSWSMan` which is a PowerShell module uploaded to the PowerShell Gallery that can install and manage the OMI libraries for you
+ Build `libpsrpclient` as well and add it to the release artifacts
+ Added Alpine 3 to the build matrix
+ Added support for reading `New-PSSessionOption -SkipCACheck -SkipCNCheck` from PowerShell instead of relying on the env vars
  + Requires PowerShell v7.2.0
  + v7.2.0 and later do not need to have `-SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)` set
  + Those options can now also control cert verification behaviour per session
  + Older versions must still set those session options and use the env vars to skip cert verification

## 1.2.1 - 2020-09-26

+ Fix build for macOS to link against OpenSSL 1.1 and not 1.0.2

## 1.2.0 - 2020-09-25

+ Added support for channel binding tokens to work with `Auth/CbtHardeningLevel = Strict`
+ Improved error messages displayed when dealing with OpenSSL errors
+ Turned on HTTPS certificate validation by default ignoring whatever is set from PowerShell
  + You still need to specify `-SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)` when creating the session in PowerShell
  + These session options are ignored in this OMI library, to disable cert verification here, set the env vars `OMI_SKIP_CA_CHECK=1` and `OMI_SKIP_CN_CHECK=1`
  + A future version may respect the `-SessionOption` skip checks in the future but until that data is actually sent to the library we opt for a safer default by always checking unless our env vars are set

## 1.1.0 - 2020-09-01

+ Added Archlinux as a known distribution

## 1.0.1 - 2020-08-20

+ Increased password length limit to allow connecting with JWT tokens to Exchange Online that routinely exceed 1KiB in size.
+ Take back point about NTLM working on macOS, while it can work when you use HTTPS, it will fail with the message encryption due to a flaw in macOS NTLM through SPNEGO mechanism

## 1.0.0 - 2020-08-19

Initial release.
