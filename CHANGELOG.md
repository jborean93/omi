# Changelog

This is the changelog for this fork of OMI.
It documents the changes in each of the tagged releases

## 1.2.0 - TBD

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
