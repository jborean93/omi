using System;
using System.Management.Automation;

namespace PSWSMan
{
    public class WSManVersion
    {
        public Version? MI { get; internal set; }
        public Version? PSRP { get; internal set; }
    }
    [Cmdlet(
        VerbsCommon.Get, "WSManVersion"
    )]
    public class GetWSManVersion : PSCmdlet
    {
        protected override void EndProcessing()
        {
            WSManVersion outputVersion = new WSManVersion()
            {
                MI = WrapGetter("mi", Native.MI_Version_Info),
                PSRP = WrapGetter("psrpclient", Native.PSRP_Version_Info),
            };

            WriteObject(outputVersion);
        }

        private delegate void VersionGetter(Native.PWSH_Version version);

        private Version? WrapGetter(string libName, VersionGetter methodDelegate)
        {
            Native.PWSH_Version rawVersion = new Native.PWSH_Version();
            try
            {
                methodDelegate(rawVersion);
                return (Version)rawVersion;
            }
            catch (Exception e)
            {
                string errMsg = "";
                string fqei = "";
                if (e is ArgumentNullException || e is DllNotFoundException)
                {
                    errMsg = String.Format(
                        "lib{0} could not be loaded, make sure it and its dependencies are available", libName);
                    fqei = String.Format("GetWSManVersionMissing.{0}", libName);

                }
                else if (e is EntryPointNotFoundException)
                {
                    errMsg = String.Format(
                        "lib{0} has not been installed, have you restarted PowerShell after installing it?", libName);
                    fqei = String.Format("GetWSManVersionNative.{0}", libName);
                }
                else
                    throw;

                ErrorRecord err = new ErrorRecord(e, fqei, ErrorCategory.NotInstalled, String.Format("lib{0}", libName));
                err.ErrorDetails = new ErrorDetails(errMsg);
                WriteError(err);
            }

            return null;
        }
    }
}
