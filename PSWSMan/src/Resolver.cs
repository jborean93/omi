using System;
using System.Management.Automation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

namespace PSWSMan
{
    internal class Resolver : IDisposable
    {
        private static readonly string PSRP_LIB_NAME = "libpsrpclient";

        private string libPath = "";
        private IntPtr libHandle = IntPtr.Zero;

        /// <summary>
        /// Load the correct 'Polyfiller' assembly based on the runtime.
        /// </summary>
        /// <param name="libPath"> </param>
        /// <param name="setPwshResolver"> </param>
        public Resolver(string libPath, bool setPwshResolver)
        {
            this.libPath = libPath;
            AssemblyLoadContext.Default.ResolvingUnmanagedDll += ResolvePSRPClient;

            // Needed if wanting to override libpsrpclient in the pwsh dir as ResolvingUnmanagedDll is only called
            // if the assembly fails to load the libary.
            if (setPwshResolver)
            {
                try
                {
                    NativeLibrary.SetDllImportResolver(typeof(PSObject).Assembly, ImportResolver);
                }
                catch (InvalidOperationException) {}  // Only 1 resolver allowed per assembly
            }
        }

        private IntPtr ImportResolver(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
        {
            return ResolvePSRPClient(assembly, libraryName);
        }

        private IntPtr ResolvePSRPClient(Assembly assembly, string libraryName)
        {
            return ResolvePSRPClient(assembly, libraryName, null);
        }

        private IntPtr ResolvePSRPClient(Assembly assembly, string libraryName, DllImportSearchPath? searchPath)
        {
            if (libraryName == PSRP_LIB_NAME)
            {
                if (libHandle == IntPtr.Zero)
                    libHandle = NativeLibrary.Load(libPath, assembly, searchPath);

                return libHandle;
            }

            return IntPtr.Zero;
        }

        public void Dispose()
        {
            if (libHandle != IntPtr.Zero)
            {
                NativeLibrary.Free(libHandle);
                libHandle = IntPtr.Zero;
            }

            AssemblyLoadContext.Default.ResolvingUnmanagedDll -= ResolvePSRPClient;
            GC.SuppressFinalize(this);
        }
        ~Resolver() { this.Dispose(); }
    }
}
