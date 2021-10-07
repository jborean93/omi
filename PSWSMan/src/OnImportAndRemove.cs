using System;
using System.Management.Automation;

namespace PSWSMan
{
    public class OnModuleImportAndRemove : IModuleAssemblyInitializer, IModuleAssemblyCleanup
    {
        private Resolver? resolver = null;

        public void OnImport()
        {
        /*
        $libPath = Join-Path $PSScriptRoot lib glibc-1.1 libpsrpclient.so
        $pwshDir = Split-Path -Path ([PSObject].Assembly.Location) -Parent
        $libPresent = Test-Path -LiteralPath (Join-Path $pwshDir libpsrpclient.so)
        */

            //Console.WriteLine("PSWSMan OnImport");
        }

        public void OnRemove(PSModuleInfo module)
        {
            //Console.WriteLine("PSWSMan OnRemove");
            resolver?.Dispose();
        }
    }
}
