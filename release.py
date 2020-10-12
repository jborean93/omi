#!/usr/bin/env python
# PYTHON_ARGCOMPLETE_OK

# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import argparse
import base64
import os
import os.path
import re
import shutil
import subprocess
import tarfile
import tempfile

from utils import (
    argcomplete,
    get_version,
    OMI_REPO,
)


def main():
    """Main program body."""
    args = parse_args()

    version = get_version()

    if args.print_tag:
        print("v%s.%s.%s-pwsh" % (version.major, version.minor, version.patch))

    elif args.output_dir:
        if os.path.exists(args.output_dir):
            shutil.rmtree(args.output_dir)
        os.makedirs(args.output_dir)

        # Create a tar.gz for each distribution libs for the GitHub release
        lib_path = os.path.join(OMI_REPO, 'PSWSMan', 'lib')
        for distribution in os.listdir(lib_path):
            artifact_dir = os.path.join(lib_path, distribution)
            artifact_tar = os.path.join(args.output_dir, distribution) + '.tar.gz'

            if distribution.startswith('.') or not os.path.isdir(artifact_dir):
                continue

            print("Creating '%s'" % artifact_tar)
            with tarfile.open(artifact_tar, 'w:gz') as tar:
                for lib_name in os.listdir(artifact_dir):
                    if lib_name == '.':
                        continue
                    print("\tAdding '%s' to tar" % lib_name)
                    tar.add(os.path.join(artifact_dir, lib_name), arcname=lib_name)

        # Create the PSWSMan nupkg
        pwsh_command = '''$ErrorActionPreference = 'Stop'

$outputDir = '%s'
$repoParams = @{
  Name = 'PSWSManRepo'
  SourceLocation = $outputDir
  PublishLocation = $outputDir
  InstallationPolicy = 'Trusted'
}
if (Get-PSRepository -Name $repoParams.Name -ErrorAction SilentlyContinue) {
    Unregister-PSRepository -Name $repoParams.Name
}
Register-PSRepository @repoParams

try {
    Publish-Module -Path ./PSWSMan -Repository $repoParams.Name
} finally {
    Unregister-PSRepository -Name $repoParams.Name
}
''' % args.output_dir
        with tempfile.NamedTemporaryFile(mode='w', suffix='.ps1') as temp_fd:
            temp_fd.write(pwsh_command)
            temp_fd.flush()

            print("Creating PSWSMan nupkg")
            subprocess.check_call(['pwsh', '-File', temp_fd.name], cwd=OMI_REPO)

        nupkg_name = None
        for name in os.listdir(args.output_dir):
            if name.endswith('.nupkg'):
                print("Published PSWSMan to '%s'" % os.path.join(args.output_dir, name))


def parse_args():
    """Parse and return args."""
    parser = argparse.ArgumentParser(description='Release helpers for the OMI library in PowerShell.')

    run_group = parser.add_mutually_exclusive_group()

    run_group.add_argument('--print-tag',
                           dest='print_tag',
                           action='store_true',
                           help='Print the tag number for the release.')

    run_group.add_argument('--output-dir',
                           dest='output_dir',
                           action='store',
                           help='The directory to create the release artifacts at.')

    if argcomplete:
        argcomplete.autocomplete(parser)

    args = parser.parse_args()

    if not args.print_tag and not args.output_dir:
        parser.error('argument --print-tag or --output-dir must be seet')

    return args


if __name__ == '__main__':
    main()
