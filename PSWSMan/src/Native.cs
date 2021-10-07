using System;
using System.Management.Automation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

namespace PSWSMan
{
    public class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        public class PWSH_Version
        {
            public Int32 Major;
            public Int32 Minor;
            public Int32 Build;
            public Int32 Revision;

            public static explicit operator Version(PWSH_Version v)
            {
                return new Version(v.Major, v.Minor, v.Build, v.Revision);
            }
        }

        [DllImport("libc")]
        public static extern void setenv(string name, string value);

        [DllImport("libc")]
        public static extern void unsetenv(string name);

        [DllImport("libc")]
        public static extern IntPtr gnu_get_libc_version();

        [DllImport("libmi")]
        public static extern void MI_Version_Info(PWSH_Version version);

        [DllImport("libpsrpclient")]
        public static extern void PSRP_Version_Info(PWSH_Version version);

        private delegate uint OpenSSL_version_num_ptr();

        public static uint OpenSSL_version_num(string[] libSSLPaths)
        {
            IntPtr lib = LoadLibrary(libSSLPaths);
            if (lib == IntPtr.Zero)
                return 0;

            try
            {
                // OpenSSL_version_num was introduced in 1.1.x, use SSLeay for older versions.
                string[] functionNames = {"OpenSSL_version_num", "SSLeay"};

                foreach (string name in functionNames)
                {
                    IntPtr functionAddr = IntPtr.Zero;
                    try
                    {
                        functionAddr = NativeLibrary.GetExport(lib, name);
                    }
                    catch (EntryPointNotFoundException) {}

                    if (functionAddr == IntPtr.Zero)
                        continue;

                    var function = (OpenSSL_version_num_ptr)Marshal.GetDelegateForFunctionPointer(
                        functionAddr, typeof(OpenSSL_version_num_ptr));
                    return function();
                }

                return 0;
            }
            finally {
                NativeLibrary.Free(lib);
            }
        }

        private delegate IntPtr OpenSSL_version_ptr(int t);

        public static string? OpenSSL_version(string[] libSSLPaths, int t)
        {
            IntPtr lib = LoadLibrary(libSSLPaths);
            if (lib == IntPtr.Zero)
                return null;

            try
            {
                IntPtr functionAddr = IntPtr.Zero;

                try
                {
                    functionAddr = NativeLibrary.GetExport(lib, "OpenSSL_version");
                }
                catch (EntryPointNotFoundException) {}

                if (functionAddr == IntPtr.Zero)
                    return null;

                var function = (OpenSSL_version_ptr)Marshal.GetDelegateForFunctionPointer(
                    functionAddr, typeof(OpenSSL_version_ptr));

                return Marshal.PtrToStringAuto(function(t));
            }
            finally {
                NativeLibrary.Free(lib);
            }
        }

        private static IntPtr LoadLibrary(string[] loadPaths)
        {
            foreach(string path in loadPaths)
            {
                IntPtr handle = IntPtr.Zero;
                try
                {
                    if (NativeLibrary.TryLoad(path, out handle))
                        return handle;
                }
                catch
                {
                    // TryLoad can actually through an exception so we just ignore it and continue on.
                    continue;
                }
            }

            return IntPtr.Zero;
        }
    }
}
