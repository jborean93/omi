# PowerShell OMI Provider Patches

These are a bunch of patches for [psl-omi-provider](https://github.com/PowerShell/psl-omi-provider) that are applied before it is built in this project.

## Patches

Here is a list of patches that are applied during the build and what they are for:

+ [1.BuildFixes.diff](1.BuildFixes.diff) - Various fixes to build `libpsrpclient` on modern platforms
+ [2.AuthenticateDefault.diff](2.AuthenticateDefault.diff) - Sets the default `-Authentication` value to `Negotiate` replicating the behaviour on Windows
+ [3.FixUnitializedVar.diff](3.FixUnitializedVar.diff) - Newer gcc compilers will fail because these vars didn't have a default value and the behaviour is undefined
+ [4.VersionInfo.diff](4.VersionInfo.diff) - Adds `PSRP_Version_Info` as an exported function and relevant build time changes to expose the version defined at build time