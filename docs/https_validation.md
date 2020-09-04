# HTTPS Certificate Validation

This documented the complicated history and current state of HTTPS certificate validation in OMI

## What is it

One of the key cornerstones of SSL/TLS connections is the ability to trust/authenticate that the server the client is connecting to is who they say they are.
It does this by checking the following about the X509 certificate presented by the server

+ The common name (`CN`) or subject alternate names (`SAN`) match the hostname the client is connecting to
  + This is not available on the Debian 8 builds due to it using an older OpenSSL build
  + The hostname checks were added in OpenSSL 1.0.2, if you are compiling this yourself you will not have this feature if you compile against an older version
+ The certificate is issued by an authority that the client trusts

There is also a third check which sees if the certificate or the certificate authority who issued it has been revoked.
This check is not implemented in the OMI codebase so it's out of scope for this document.

## How to Use in PowerShell

When connecting to a HTTPS endpoint in PowerShell on Linux you need use the `-UseSSL` parameters and add the options to skip the certificate validation like so:

```powershell
$invokeParams = @{
    ComputerName = 'hostname.domain.com'
    Authentication = 'Negotiate'
    UseSSL = $true
    SessionOption = (New-PSSessionOption -SkipCACheck -SkipCNCheck)
}
Invoke-Command @invokeParams
```

There's a hardcoded check in PowerShell that makes sure you have the `-SkipCACheck` and `-SkipCNCheck` session option when creating a HTTPS endpoint.
This is because historically the upstream OMI library never did any validation so PowerShell wanted to make sure you were explicitly aware that you are skipping one of the core tenants of a HTTPS connection.

Since the `1.2.0` release of this fork, certificate validation has been implemented and enabled by default.
The `-SkipCACheck` and `-SkipCNCheck` session options must still be set in PowerShell but they are ignored by OMI (because they are never passed through).
This means that connecting to a HTTPS endpoint using this library will always validate the server's certificate regardless of the options passed in by PowerShell.

## Disabling Validation

If you truly want to disable certificate validation then you need to set the following environment variables to `1`:

+ `OMI_SKIP_CA_CHECK`: Like `-SkipCACheck` it will not validate the cert has been signed and issued by a authority the client trusts
+ `OMI_SKIP_CN_CHECK`: Like `-SkipCNCheck` it will still validate the CA chain of the cert but it will not verify the hostname matches the cert `CN` or `SAN` entries

There is no equivalent for `-SkipRevocationCheck` as there is no revocation checks that occur at this point in time.

While .NET/PowerShell has an easy way to set env vars, the way it is written in .NET on non-Windows platforms is to keep a copy of the env vars being managed specifically for the .NET applications.
This means running `$env:OMI_SKIP_CA_CHECK = '1'` will only affect applications running in the .NET space and the OMI library will not be able to see that var.
If you wish to set or unset an env var during runtime you need to use PInvoke to call `setenv` and `unsetenv` like so:

```powershell
Add-Type -Namespace OMI -Name Environment -MemberDefinition @'
[DllImport("libc")]
public static extern void setenv(string name, string value);

[DllImport("libc")]
public static extern void unsetenv(string name);
'@

# To disable cert validation
[OMI.Environment]::setenv('OMI_SKIP_CA_CHECK', '1')
[OMI.Environment]::setenv('OMI_SKIP_CN_CHECK', '1')

# To re-enable cert validation
[OMI.Environment]::unsetenv('OMI_SKIP_CA_CHECK')
[OMI.Environment]::unsetenv('OMI_SKIP_CN_CHECK')
```

You can also set the var when you start the process, you only need to use the PInvoke process in PowerShell if you wish to set/change/unset one of these vars once the process has started.
Because this behaviour is set by an environment variable, it is globally set for a process and cannot be adjusted for an individual connection.
You can turn it off and on during the process using the method above.

## Future Changes in PowerShell

The end goal would be to remove the requirement for setting `-SkipCACheck` and `-SkipCNCheck` in PowerShell and actually have those options control the verification behaviour in this OMI library.
This is not an easy task as the current behaviour in PowerShell is designed to address limitations in the OMI library that it ships.
Maybe in the future if this fork of OMI gets shipped with PowerShell we can drop the requirement for setting those options and actually have them get passed through to OMI.

For now I'm happy that this fork will validate the certificate by default making a HTTPS connection more secure but still provide a way to opt out using the env vars.

## Trusting a CA Chain

The method for trusting a CA chain for use in OMI is a complicated one.
It is highly dependent on the distribution being used and what OpenSSL library was linked to the compiled OMI library.
Validation is handled by OpenSSL exclusively so the logic for determining the list of trusted CAs is dependent on how OpenSSL was configured and installed which can differ across the various distributions.
If you wish to ignore the default system location and provide your own chain of certificate authorities you can set one of these 2 environment variables:

+ `SSL_CERT_DIR`
  + Directory containing CA certificates in the PEM format
  + Each file contains one CA certificate to trust
  + The files are looked up by the CA subject name hash value
  + The dir *SHOULD* have been prepared with the [c_rehash](https://www.openssl.org/docs/manmaster/man1/c_rehash.html) tool to ensure the files have the correct name
  + This is useful if you want to manage a collection of CAs to trust as individual files
  + It is easier to use `SSL_CERT_FILE` if you have your own CA chain that needs to be trusted
+ `SSL_CERT_FILE`:
  + File containing 1 or more CA certificates in the PEM format
  + Unlike `SSL_CERT_DIR` this is just a file but it can contain multiple certificates to trust
  + No need to use a tool to generate the file

More information on these 2 env vars can be found on the OpenSSL [SSL_CTX_load_verify_locations](https://www.openssl.org/docs/manmaster/man3/SSL_CTX_load_verify_locations.html) docs.

_Note: Self signed certificates used on the WinRM endpoint cannot be trusted. It must be issued by a CA and then the CA is added to your trust store for OpenSSL to verify the cert properly._

The alternative is to add your CA to the system store that OpenSSL is configured to read.
This allows you to reutilise that CA for other applications that also use OpenSSL without requiring that env var to always be set.
The downside is that the paths differ based on the Linux distribution used.

_Note: Adding a CA chain to the system store means any other application will now trust that authority. Only do this if you are truly ok with that._

### Linux

There are multiple locations that is used to manage certificates on a Linux distribution.
Each distribution can use different paths and commands to keep things in sync so this is a breakdown of each one.

| Distro | Staging Path | Sync Command | c_rehash Package | System Trust Dir | System Trust File Bundle |
| ------ | ------------ | -----------  | ---------------- | ---------------- | ------------------------ |
| Arch | /etc/ca-certificates/trust-source/anchors | update-ca-trust extract | openssl | /etc/ssl/certs | /etc/ssl/certs/ca-certificates.crt |
| CentOS/RHEL | /etc/pki/ca-trust/source/anchors | update-ca-trust extract | openssl-perl | /etc/pki/tls/certs | /etc/pki/tls/certs/ca-bundle.crt |
| Fedora | /etc/pki/ca-trust/source/anchors | update-ca-trust extract | openssl-perl | /etc/pki/tls/certs | /etc/pki/tls/certs/ca-bundle.crt |
| Debian | /usr/local/share/ca-certificates⁰ | update-ca-certificates | openssl | /etc/ssl/certs | /etc/ssl/certs/ca-certificates.crt |
| Ubuntu | /usr/local/share/ca-certificates⁰ | update-ca-certificates | openssl | /etc/ssl/certs | /etc/ssl/certs/ca-certificates.crt |

⁰ - CA chains in the staging path or trust dir must have the extension `.crt` but they are still `PEM` encoded.

The `Staging Path` is the path to copy your CA chain to.
The `Sync Command` is the command to run to add any of the certs in the `Staging Path` to the default store.
The `c_rehash Package` is the name of the package to install for the distribution to install the `c_rehash` utility.
The `System Trust Dir` and `System Trust File Bundle` is the default value for `SSL_CERT_DIR` and `SSL_CERT_FILE` respectively.
The shouldn't be adding certs to the `System Trust Dir` or `System Trust File Bundle` manually, using the staging process instead.

When adding a new CA chain to your OS it is recommended to copy it to the `Staging Path` then run the `Sync Command`.
The `Sync Command` will copy the CA chain in the staging dir to the proper location(s) and it should be trusted by OpenSSL from there onwards.
If you don't wish to add the CA chain to the system wide trust store you should use the `SSL_CERT_DIR` or `SSL_CERT_FILE` env vars to specify your own managed store.

### macOS

Cert validation on macOS has it's own quirks that set it apart from Linux.
The OMI library is linked against OpenSSL that is installed from `brew` and not the TLS library that comes builtin to macOS.
When you install `openssl` with `brew`, the install process will take a copy of the existing system keychain and place it into a directory it itself uses.
Any libraries that are linked to this OpenSSL install will use that directory and not the system keychain.
Ultimately this means that it will trust any CAs that were present in the macOS keychain when OpenSSL was installed but if you wish to add any more CAs you need to add it yourself.

The docs for the [openssl@1.1](https://formulae.brew.sh/formula/openssl@1.1#default) formula state to add additional certificates do the following:

```bash
# Add the PEM files into this directory
$(brew --prefix)/etc/openssl@1.1/certs

# Make sure c_rehash is run to pre the dir now there are more certs
$(brew --prefix)/opt/openssl@1.1/bin/c_rehash
```

I no longer deal with macOS on a regular basis so this information may change at any time in the future.
