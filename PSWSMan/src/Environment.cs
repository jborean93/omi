namespace PSWSMan
{
    internal class Environment
    {
        public static void SetEnv(string name, string value)
        {
            // We need to use the native setenv call as .NET keeps it's own register of env vars that are separate from
            // the process block that native libraries like libmi sees. We still set the .NET env var to keep things in
            // sync.
            Native.setenv(name, value);
            System.Environment.SetEnvironmentVariable(name, value);
        }

        public static void UnsetEnv(string name)
        {
            // We need to use the native unsetenv call as .NET keeps it's own register of env vars that are separate
            // from the process block that native libraries like libmi sees. We still unset the .NET env var to keep
            // things in sync.
            Native.unsetenv(name);
            System.Environment.SetEnvironmentVariable(name, null);
        }
    }
}
