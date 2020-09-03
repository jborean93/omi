# Changelog

This is the changelog for this fork of OMI.
It documents the changes in each of the tagged releases

## 1.2.0 - TBD

+ Added support for channel binding tokens to work with `Auth/CbtHardeningLevel = Strict`
+ Improved error messages displayed when dealing with OpenSSL errors

## 1.1.0 - 2020-09-01

+ Added Archlinux as a known distribution

## 1.0.1 - 2020-08-20

+ Increased password length limit to allow connecting with JWT tokens to Exchange Online that routinely exceed 1KiB in size.
+ Take back point about NTLM working on macOS, while it can work when you use HTTPS, it will fail with the message encryption due to a flaw in macOS NTLM through SPNEGO mechanism

## 1.0.0 - 2020-08-19

Initial release.
