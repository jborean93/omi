using System.Management.Automation;

namespace PSWSMan
{
    [Cmdlet(
        VerbsLifecycle.Disable, "WSManCertVerification",
        DefaultParameterSetName = "Individual"
    )]
    public class DisableWSManCertVerification : PSCmdlet
    {
        [Parameter(
            ParameterSetName = "Individual"
        )]
        public SwitchParameter CACheck { get; set; }

        [Parameter(
            ParameterSetName = "Individual"
        )]
        public SwitchParameter CNCheck { get; set; }

        [Parameter(
            ParameterSetName = "All"
        )]
        public SwitchParameter All { get; set; }

        protected override void EndProcessing()
        {
            if (All.IsPresent)
            {
                CACheck = true;
                CNCheck = true;
            }

            if (CACheck)
                Environment.SetEnv("OMI_SKIP_CA_CHECK", "1");

            if (CNCheck)
                Environment.SetEnv("OMI_SKIP_CN_CHECK", "1");
        }
    }

    [Cmdlet(
        VerbsLifecycle.Enable, "WSManCertVerification",
        DefaultParameterSetName = "Individual"
    )]
    public class EnableWSManCertVerification : PSCmdlet
    {
        [Parameter(
            ParameterSetName = "Individual"
        )]
        public SwitchParameter CACheck { get; set; }

        [Parameter(
            ParameterSetName = "Individual"
        )]
        public SwitchParameter CNCheck { get; set; }

        [Parameter(
            ParameterSetName = "All"
        )]
        public SwitchParameter All { get; set; }

        protected override void EndProcessing()
        {
            if (All.IsPresent)
            {
                CACheck = true;
                CNCheck = true;
            }

            if (CACheck)
                Environment.UnsetEnv("OMI_SKIP_CA_CHECK");

            if (CNCheck)
                Environment.UnsetEnv("OMI_SKIP_CN_CHECK");
        }
    }
}
