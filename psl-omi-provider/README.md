# PowerShell OMI Provider Patches

These are a bunch of patches for [psl-omi-provider](https://github.com/PowerShell/psl-omi-provider) that are applied before it is built in this project.

## Patches

Here is a list of patches that are applied during the build and what they are for:

+ [1.BuildFixes.diff](1.BuildFixes.diff) - Various fixes to build `libpsrpclient` on modern platforms
+ [2.AuthenticateDefault.diff](2.AuthenticateDefault.diff) - Sets the default `-Authentication` value to `Negotiate` replicating the behaviour on Windows
