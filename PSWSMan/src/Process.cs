using System;
using System.Diagnostics;
using System.Text;

namespace PSWSMan
{
    public class ProcessResult
    {
        public string Stdout { get; internal set; } = "";
        public string Stderr { get; internal set; } = "";
        public int ExitCode { get; internal set; } = 0;
    }

    public class Process
    {
        public static ProcessResult Exec(string filePath, params string[] arguments)
        {
            System.Diagnostics.Process proc = new System.Diagnostics.Process();
            proc.StartInfo.FileName = filePath;
            proc.StartInfo.Arguments = String.Join(" ", arguments);

            proc.StartInfo.RedirectStandardOutput = true;
            StringBuilder stdout = new StringBuilder();
            proc.OutputDataReceived += (object sender, DataReceivedEventArgs e) =>
            {
                stdout.AppendLine(e.Data);
            };

            proc.StartInfo.RedirectStandardError = true;
            StringBuilder stderr = new StringBuilder();
            proc.ErrorDataReceived += (object sender, DataReceivedEventArgs e) =>
            {
                stderr.AppendLine(e.Data);
            };

            proc.Start();
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            proc.WaitForExit();

            return new ProcessResult()
            {
                Stdout = stdout.ToString(),
                Stderr = stderr.ToString(),
                ExitCode = proc.ExitCode,
            };
        }
    }
}
