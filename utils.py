# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import json
import os
import os.path
import subprocess
import sys

try:
    import argcomplete
except ImportError:
    argcomplete = None


OMI_REPO = os.path.abspath(os.path.dirname(__file__))


def build_bash_script(steps):  # type: (List[Tuple[str, str]]) -> str
    """ Generates a bash script based on the steps specified. """
    script = '#!/usr/bin/env bash\n\nset -o pipefail -eu'

    for step_name, step_script in steps:
        step_name = '| ' + step_name.center(76) + ' |'
        step_border = '-' * len(step_name)
        script += '''
echo ""
echo "{0}"
echo "{1}"
echo "{0}"
echo ""
{2}
'''.format(step_border, step_name, step_script)

    return script


def build_multiline_command(command, extras):  # type: (str, List[str]) -> str
    """ Generates a command that spans multiple lines per option. """
    return '%s \\\n    %s' % (command, ' \\\n    '.join(extras))


def build_package_command(package_manager, packages):  # type: (str, List[str]) -> str
    """ Generates a command to install packages for a specific package manager. """
    package_boilerplate = {
        'apt': 'apt-get -q update\nDEBIAN_FRONTEND=noninteractive apt-get -q install -y',
        'dnf': 'dnf install -y -q',
        'brew': 'brew install',
        'pacman': 'pacman -Sy --noconfirm --overwrite \'*\'',
        'yum': 'yum install -y -q',
    }

    if package_manager not in package_boilerplate:
        raise ValueError("Unknown package manager '%s', valid package managers: '%s'"
                         % (package_manager, "', '".join(package_boilerplate.keys())))

    if package_manager == 'brew':
        brew_packages = []
        cask_packages = []

        for package in packages:
            if package.startswith('brew:'):
                cask_packages.append(package[5:])

            else:
                brew_packages.append(package)

        package_command = build_multiline_command(package_boilerplate[package_manager], brew_packages)
        if cask_packages:
            package_command += '\n\n' + build_multiline_command('brew cask install', cask_packages)

    elif package_manager == 'pacman':
        pacman_packages = set()
        aur_packages = set()

        for package in packages:
            if package.startswith('aur:'):
                # Installing an AUR package requires some extra binaries
                pacman_packages.update({'base-devel', 'git', 'sudo'})
                aur_packages.add(package[4:])

            else:
                pacman_packages.add(package)

        package_command = build_multiline_command(package_boilerplate[package_manager], pacman_packages)

        # gss-ntlmssp in AUR doesn't seem to work, just build it ourselves for now
        if 'gss-ntlmssp' in aur_packages:
            aur_packages.remove('gss-ntlmssp')
            package_command += '\n' + '''
git clone https://github.com/gssapi/gss-ntlmssp.git /tmp/gss-ntlmssp
pushd /tmp/gss-ntlmssp
autoreconf -f -i
./configure
make && make install
popd
rm -rf /tmp/gss-ntlmssp

mkdir -p /etc/gss/mech.d
echo "gssntlmssp_v1    1.3.6.1.4.1.311.2.2.10    /usr/local/lib/gssntlmssp/gssntlmssp.so" > /etc/gss/mech.d/ntlm.conf'''

        if aur_packages:
            # We cannot run makpkg as root so we need to create another user
            package_command += '\n' + '''
AUR_USER=aur_user

echo "Creating aur user for running makepg"
useradd -m "${AUR_USER}"
echo "${AUR_USER}:" | chpasswd -e
echo "${AUR_USER}      ALL = NOPASSWD: ALL" >> /etc/sudoers

AUR_PACKAGES=('%s')
for PACKAGE in "${AUR_PACKAGES[@]}"; do
    echo "Installing ${PACKAGE} from AUR"

    PACKAGE_DIR="/tmp/${PACKAGE}"
    git clone "https://aur.archlinux.org/${PACKAGE}.git" "${PACKAGE_DIR}"
    chmod 777 "${PACKAGE_DIR}"

    pushd "${PACKAGE_DIR}"
    su "${AUR_USER}" -c 'makepkg --install --noconfirm --syncdeps'
    popd
    rm -rf "${PACKAGE_DIR}"
done''' % "' '".join(aur_packages)

    else:
        package_command = build_multiline_command(package_boilerplate[package_manager], packages)

    return package_command


def build_package_repo_command(package_manager, repository):  # type: (str, str) -> str
    """ Generates a command to install a package repo for a specific package manager. """
    if package_manager == 'apt':
        command = build_package_command('apt', ['apt-transport-https', 'wget'])
        command += '''
wget -q -O repo.deb %s
dpkg -i repo.deb
rm -f repo.deb''' % repository
        return command

    elif package_manager == 'brew':
        return 'echo "Not applicable on macOS"'

    elif package_manager == 'pacman':
        return 'echo "Not applicable on Archlinux"'

    elif package_manager in ['yum', 'dnf']:
        return 'curl -s %s | tee /etc/yum.repos.d/microsoft.repo' % repository

    else:
        raise ValueError("Unknown package manager '%s', valid package managers: 'apt', 'brew', 'yum', 'dnf'"
                         % package_manager)


def complete_distribution():  # type: () -> List[str]
    """ Finds valid distributions that this repo knows how to build for. """
    distributions = []

    if sys.platform == 'darwin':
        distributions.append('macOS')

    for path in os.listdir(os.path.join(OMI_REPO, 'distribution_meta')):
        full_path = os.path.join(OMI_REPO, 'distribution_meta', path)

        if not os.path.isfile(full_path) or not path.endswith('.json') or path == 'macOS.json':
            continue

        distributions.append(os.path.splitext(path)[0])

    return distributions


def docker_run(image, script, cwd='/omi', env=None, interactive=False):
    # type: (str, str, str, Optional[Dict[str, str]], bool) -> None
    """ Runs docker run with the arguments specified. """
    docker_args = [
        'docker', 'run', '--rm',
        '-w', cwd,
        '-v', '%s:/omi:Z' % OMI_REPO,
    ]

    if interactive:
        docker_args.append('-it')

    if env:
        for key, value in env.items():
            docker_args.extend(['-e', '%s=%s' % (key, value)])

    docker_args.extend([image, '/bin/bash', script])

    print("Starting docker with: %s" % " ".join(docker_args))
    subprocess.check_call(docker_args)


def load_distribution_config(distribution):  # type: (str) -> Dict[str, any]
    """ Loads the distribution json and validates the structure. """
    with open(os.path.join(OMI_REPO, 'distribution_meta', '%s.json' % distribution), mode='rb') as fd:
        distro_details = json.loads(fd.read().decode('utf-8'))

    required_keys = {'package_manager', 'build_deps', 'microsoft_repo', 'test_deps'}
    optional_keys = {'container_image'}
    valid_keys = required_keys.union(optional_keys)
    actual_keys = set(distro_details.keys())

    missing_keys = required_keys.difference(actual_keys)
    if missing_keys:
        raise ValueError("Package json for %s does not contain the required keys '%s'"
                         % (distribution, "', '".join(missing_keys)))

    extra_keys = actual_keys.difference(valid_keys)
    if extra_keys:
        raise ValueError("Package json for %s has the following extra keys '%s'"
                         % (distribution, "', '".join(extra_keys)))

    for key in valid_keys:
        if key not in distro_details:
            distro_details[key] = None

    list_keys = ['build_deps', 'test_deps']
    for key in list_keys:
        if not isinstance(distro_details[key], list):
            distro_details[key] = [distro_details[key]]

        distro_details[key] = [v for v in distro_details[key] if v]

    return distro_details


def select_distribution(args):
    """ Selects the distribution from the args or prompts the user. """
    valid_distributions = sorted(complete_distribution())

    if args.distribution:
        if args.distribution not in valid_distributions:
            raise ValueError("Invalid distribution choice '%s', valid distribution: '%s'"
                             % (args.distribution, "', '".join(valid_distributions)))

        distribution = args.distribution

    else:
        valid_responses = set(valid_distributions)
        valid_responses.add('q')

        msg = "Select your distribution (q to quit):\n    %s\n" % "\n    ".join(valid_distributions)
        distribution = ''
        while distribution not in valid_responses:
            if sys.version_info[0] == 2:
                distribution = raw_input(msg)

            else:
                distribution = input(msg)

        if distribution.lower() == 'q':
            return

    return distribution
