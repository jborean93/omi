#!/usr/bin/env python
# PYTHON_ARGCOMPLETE_OK

# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import argparse
import os
import os.path
import re
import subprocess
import tempfile

from utils import (
    argcomplete,
    build_bash_script,
    build_multiline_command,
    build_package_command,
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

    script_steps = [('Getting current directory path', 'OMI_REPO="$( pwd )"')]
    output_dirname = 'build-%s' % distribution

    if not args.skip_deps:
        dep_script = build_package_command(distro_details['package_manager'], distro_details['build_deps'])
        script_steps.append(('Installing build pre-requisite packages', dep_script))

    # Do this in the container as selinux could have these folders be under root
    if not args.skip_clear:
        rm_script = '''cd Unix
if [ -d "{0}" ]; then
    rm -rf "{0}"
fi'''.format(output_dirname)
        script_steps.append(('Entering OMI source folder and cleaning any existing build', rm_script))

    configure_args = [
        '--outputdirname="%s"' % output_dirname,
        '--prefix="%s"' % args.prefix,
    ]
    if args.debug:
        configure_args.append('--enable-debug')

    # macOS on Azure Pipelines has OpenSSL 1.0.2 installed but we want to compile against the OpenSSL version in our
    # dep list which is openssl@1.1. Because the deps are installed at runtime we need our build script to find that
    # value and add to our configure args.
    if distribution == 'macOS':
        script_steps.append(('Getting OpenSSL locations for macOS',
            'OPENSSL_PREFIX="$(brew --prefix openssl@1.1)"'))

        configure_args.extend([
            '--openssl="${OPENSSL_PREFIX}/bin/openssl"',
            '--opensslcflags="-I${OPENSSL_PREFIX}/include"',
            '--openssllibs="-L${OPENSSL_PREFIX}/lib -lssl -lcrypto -lz"',
            '--openssllibdir="${OPENSSL_PREFIX}/lib"',
        ])

    configure_script = build_multiline_command('./configure', configure_args)

    script_steps.append(('Running configure', configure_script))
    script_steps.append(('Running make', 'make'))

    script_steps.append(('Cloning upstream psl-omi-provider repo',
        '''if [ -d "{0}" ]; then
    rm -rf "{0}"
fi
git clone https://github.com/PowerShell/psl-omi-provider.git "{0}"
cd "{0}"'''.format('/tmp/psl-omi-provider')))

    # Get a list of patches to apply to psl-omi-provider and sort them by the leading digit in the filename.
    psl_patches = [p for p in os.listdir(os.path.join(OMI_REPO, 'psl-omi-provider'))
        if re.match(r'^\d+\..*\.diff$', p)]
    psl_patches.sort(key=lambda p: int(p.split('.')[0]))

    script_steps.append(('Applying psl-omi-provider patches',
        '\n'.join(['git apply "${OMI_REPO}/psl-omi-provider/%s"' % p for p in psl_patches])))

    built_type = 'Debug' if args.debug else 'Release'
    library_extension = 'dylib' if distribution == 'macOS' else 'so'
    script_steps.append(('Building libpsrpclient', '''rm -rf omi
ln -s "${{OMI_REPO}}" omi

if [ -e omi/Unix/output ]; then
    rm omi/Unix/output
fi
ln -s {0} omi/Unix/output

cd src
cmake -DCMAKE_BUILD_TYPE={1} .
make psrpclient
cp libpsrpclient.{2} "${{OMI_REPO}}/Unix/{0}/lib/"'''.format(output_dirname, built_type, library_extension)))

    if distribution == 'macOS':
        script_steps.append(('Patch libmi dylib path for libpsrpclient', '''install_name_tool -change \\
    '{0}/lib/libmi.dylib' \\
    '@executable_path/libmi.dylib' \\
    "${{OMI_REPO}}/Unix/{1}/lib/libpsrpclient.dylib"'''.format(args.prefix, output_dirname)))

    build_script = build_bash_script(script_steps)

    if args.output_script:
        print(build_script)

    else:
        with tempfile.NamedTemporaryFile(dir=OMI_REPO, prefix='build-', suffix='-%s.sh' % distribution) as temp_fd:
            temp_fd.write(build_script.encode('utf-8'))
            temp_fd.flush()

            configure_dir = os.path.join(OMI_REPO, 'Unix')
            build_dir = os.path.join(configure_dir, output_dirname)

            if args.docker:
                env_vars = {}
                for key, value in os.environ.items():
                    if key.startswith('OMI_BUILDVERSION_'):
                        env_vars[key] = value

                docker_run(distro_details['container_image'], '/omi/%s' % os.path.basename(temp_fd.name),
                    cwd='/omi', env=env_vars)

            else:
                print("Running build locally")
                subprocess.check_call(['bash', temp_fd.name], cwd=OMI_REPO)

            libmi_path = os.path.join(build_dir, 'lib', 'libmi.%s' % library_extension)
            print("Library has been successfully build at '%s'" % libmi_path)


def parse_args():
    """Parse and return args."""
    parser = argparse.ArgumentParser(description='Build OMI and generate the libmi library.')

    parser.add_argument('distribution',
                        metavar='distribution',
                        nargs='?',
                        default=None,
                        help='The distribution to build.').completer = complete_distribution

    parser.add_argument('--debug',
                        dest='debug',
                        action='store_true',
                        help='Whether to produce a debug build.')

    parser.add_argument('--prefix',
                        dest='prefix',
                        default='/opt/omi',
                        action='store',
                        help='The defined prefix of the OMI build (default=/opt/omi).')

    parser.add_argument('--skip-clear',
                        dest='skip_clear',
                        action='store_true',
                        help="Don't clear any existing build files for the distribution.")

    parser.add_argument('--skip-deps',
                        dest='skip_deps',
                        action='store_true',
                        help='Skip installing any dependencies.')

    run_group = parser.add_mutually_exclusive_group()
    run_group.add_argument('--docker',
                           dest='docker',
                           action='store_true',
                           help='Whether to build OMI in a docker container.')

    run_group.add_argument('--output-script',
                           dest='output_script',
                           action='store_true',
                           help='Will print out the bash script that can build the library.')

    if argcomplete:
        argcomplete.autocomplete(parser)

    args = parser.parse_args()

    return args


if __name__ == '__main__':
    main()