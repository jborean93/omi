#!/usr/bin/env python
# PYTHON_ARGCOMPLETE_OK

# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import argparse
import os.path
import subprocess
import tempfile

from utils import (
    argcomplete,
    build_bash_script,
    build_package_command,
    build_package_repo_command,
    complete_distribution,
    docker_run,
    load_distribution_config,
    OMI_REPO,
    select_distribution,
)


def main():
    """Main program body."""
    args = parse_args()
    distribution = select_distribution(args)
    if not distribution:
        return

    distro_details = load_distribution_config(distribution)
    if args.docker and not distro_details['container_image']:
        raise ValueError("Cannot run --docker on %s as no container_image has been specified" % distribution)

    script_steps = []
    if not args.skip_deps:
        repo_script = build_package_repo_command(distro_details['package_manager'], distro_details['microsoft_repo'])
        dep_script = build_package_command(distro_details['package_manager'], distro_details['test_deps'])

        script_steps.append(('Setting up the Microsoft package manager repo', repo_script))

        if distribution == 'debian8':
            debian_ms = 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-debian-jessie-prod jessie main" > /etc/apt/sources.list.d/microsoft.list'
            script_steps.append(('Further steps for MS repo on Debian 8', debian_ms))

        elif distribution == 'debian9':
            debian_ms = 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-debian-stretch-prod stretch main" > /etc/apt/sources.list.d/microsoft.list'
            script_steps.append(('Further steps for MS repo on Debian 8', debian_ms))

        script_steps.append(('Installing test dependency packages', dep_script))

        cert_extension = distro_details['cert_extension'] if distro_details['cert_extension'] else 'pem'
        ca_trust_script = '''cp integration_environment/cert_setup/ca.pem '%s/ca.%s'
%s''' % (distro_details['cert_staging_dir'], cert_extension, distro_details['cert_staging_cmd'])
        script_steps.append(('Adding CA chain to system trust store', ca_trust_script))

        pwsh_deps = '''cat > /tmp/pwsh-requirements.ps1 << EOL
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'

Install-Module -Name Pester -MinimumVersion 5.0 -Force
Install-Module -Name powershell-yaml -Force
Install-Module -Name MSAL.PS -Force -AcceptLicense
EOL
pwsh -NoProfile -NoLogo -File /tmp/pwsh-requirements.ps1'''
        script_steps.append(('Installing Pester 5+ and other PowerShell deps', pwsh_deps))


    # On macOS we aren't running as root in a container so this step needs sudo.
    sudo_prefix = 'sudo ' if distribution == 'macOS' else ''
    copy_script = '''PWSHDIR="$( dirname "$( readlink "$( which pwsh )" )" )"
%s/bin/cp Unix/build-%s/lib/libmi.* "${PWSHDIR}/"''' % (sudo_prefix, distribution)
    script_steps.append(('Copying libmi.so to the PowerShell directory', copy_script))

    pester_script = '''cat > /tmp/pwsh-test.ps1 << EOL
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
Import-Module -Name Pester -MinimumVersion 5.0

\$configuration = [PesterConfiguration]::Default
\$configuration.Output.Verbosity = 'Detailed'
\$configuration.Run.Path = 'libmi.tests.ps1'
\$configuration.Run.Exit = \$true
Invoke-Pester -Configuration \$configuration
EOL

echo "%s" > /tmp/distro.txt''' % distribution
    script_steps.append(('Creating Pester test script', pester_script))

    script_steps.append(('Getting PowerShell version', 'pwsh -Command \$PSVersionTable'))

    if distribution == 'macOS':
        script_steps.append(('Output libmi libraries', 'otool -L "${PWSHDIR}/libmi.dylib"'))

    else:
        script_steps.append(('Output libmi libraries', 'ldd "${PWSHDIR}/libmi.so"'))

    if args.interactive:
        script_steps.append(('Opening interactive shell', '/bin/bash'))

    else:
        script_steps.append(('Running PowerShell test', 'pwsh -NoProfile -NoLogo -File /tmp/pwsh-test.ps1'))

    test_script = build_bash_script(script_steps)

    if args.output_script:
        print(test_script)

    else:
        with tempfile.NamedTemporaryFile(dir=OMI_REPO, prefix='test-', suffix='-%s.sh' % distribution) as temp_fd:
            temp_fd.write(test_script.encode('utf-8'))
            temp_fd.flush()

            if args.docker:
                docker_run(distro_details['container_image'], '/omi/%s' % os.path.basename(temp_fd.name),
                    env={'KRB5_CONFIG': '/omi/krb5.conf'}, interactive=args.interactive)

            else:
                print("Running tests locally")
                subprocess.check_call(['bash', temp_fd.name], cwd=OMI_REPO)


def parse_args():
    """Parse and return args."""
    parser = argparse.ArgumentParser(description='Test the OMI library in PowerShell.')

    parser.add_argument('distribution',
                        metavar='distribution',
                        nargs='?',
                        default=None,
                        help='The distribution to test.').completer = complete_distribution

    parser.add_argument('--interactive',
                        dest='interactive',
                        action='store_true',
                        help='When combined with --docker will start an interactive session in the test container.')

    parser.add_argument('--skip-deps',
                        dest='skip_deps',
                        action='store_true',
                        help='Skip installing any dependencies.')

    run_group = parser.add_mutually_exclusive_group()
    run_group.add_argument('--docker',
                           dest='docker',
                           action='store_true',
                           help='Whether to test OMI in a docker container.')

    run_group.add_argument('--output-script',
                           dest='output_script',
                           action='store_true',
                           help='Will print out the bash script that can test the library.')

    if argcomplete:
        argcomplete.autocomplete(parser)

    args = parser.parse_args()

    if args.interactive and not args.docker:
        parser.error('arguement --interactive: must be set with argument --docker')

    return args


if __name__ == '__main__':
    main()
