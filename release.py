#!/usr/bin/env python
# PYTHON_ARGCOMPLETE_OK

# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import argparse
import os
import os.path

from utils import (
    argcomplete,
    OMI_REPO,
)


def main():
    """Main program body."""
    args = parse_args()

    if args.print_tag:
        with open(os.path.join(OMI_REPO, 'omi.version'), mode='r') as fd:
            version_lines = fd.read().splitlines()

        version_info = {}
        for line in version_lines:
            k, v = line.split('=', 1)
            version_info[k] = v

        print("v%s.%s.%s-pwsh" % (version_info['OMI_BUILDVERSION_MAJOR'], version_info['OMI_BUILDVERSION_MINOR'],
                                  version_info['OMI_BUILDVERSION_PATCH']))

    elif args.pipeline_artifacts:
        # This renames the Azure DevOps pipeline files to the format desired for a GitHub release asset
        for name in os.listdir(args.pipeline_artifacts):
            if not name.endswith('-libmi'):
                continue

            artifact_dir = os.path.join(args.pipeline_artifacts, name)

            distribution = name.rstrip('-libmi')
            lib_name = os.listdir(artifact_dir)[0]
            lib_ext = os.path.splitext(lib_name)[-1]

            src_path = os.path.join(artifact_dir, lib_name)
            dest_path = os.path.join(args.pipeline_artifacts, 'libmi-%s%s' % (distribution, lib_ext))

            print("Renaming '%s' -> '%s'" % (src_path, dest_path))
            os.rename(src_path, dest_path)
            os.rmdir(artifact_dir)


def parse_args():
    """Parse and return args."""
    parser = argparse.ArgumentParser(description='Release helpers for the OMI library in PowerShell.')

    run_group = parser.add_mutually_exclusive_group()

    run_group.add_argument('--print-tag',
                           dest='print_tag',
                           action='store_true',
                           help='Print the tag number for the release.')

    run_group.add_argument('--pipeline-artifacts',
                           dest='pipeline_artifacts',
                           action='store',
                           help='The Azure DevOps pipeline artifact store directory to process.')

    if argcomplete:
        argcomplete.autocomplete(parser)

    args = parser.parse_args()

    if not args.print_tag and not args.pipeline_artifacts:
        parser.error('argument --print-tag or --pipeline-artifacts must be seet')

    return args


if __name__ == '__main__':
    main()
