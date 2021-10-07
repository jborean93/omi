# Testing

Testing the changes in these libraries is quite complex.
The [integration_environment](../integration_environment) folder has a Vagrant/Ansible setup that will set up a test environment for you.
This test environment contains 2 hosts:

+ DC01 - Windows domain controller
+ DEBIAN10 - A Linux test host with Docker and the local `omi` repo copied to `~/omi`

To create this environment, run the following:

```bash
cd integration_environment
vagrant up
ansible-playbook main.yml -vv

# To setup the host with pre-built variable from an Azure DevOps CI run, add '-e build_id=<build id>' for that run
ansible-playbook main.yml -vv -e build_id=123
```

The `build_id` variable can be set to any build number from [Azure DevOps jborean93.omi](https://dev.azure.com/jborean93/jborean93/_build?definitionId=6&_a=summary).
When set, the playbook will download the PSWSMan nupkg from the run and place it into `build`.
If you don't specify `build_id` it will just copy whatever files that are located in the localhost to the Debian host.

You can also specify the following `--tags` to only run a specific component of the `main.yml` playbook:

+ `windows`: Setup the Windows domain controller
+ `linux`: Setup the Debian host
+ `build_artifacts`: Run the Azure DevOps libmi download tasks, `-e build_id=` must also be set

The domain information and credentials are dependent on the values in [integration_environment/inventory.yml](../integration_environment/inventory.yml).
It defaults to a domain called `omi.test` with the test user `omi@OMI.TEST` with the password `Password01`.
The environment comes prebuilt to allow you to run the [libmi.tests.ps1](../libmi.tests.ps1) [Pester](https://github.com/pester/Pester) tests in various distribution Docker containers.
To run tests for all the distributions run the following:

```bash
cd integration_environment
ansible-playbook test.yml -vv

# Run the tests for only 1 distribution, add '-e distribution=<distribution>'
ansible-playbook test.yml -vv -e distribution=centos8
```

If you wish to run more tests manually in the test environment you can log onto the `DEBIAN10` host and start up your own test container with:

```bash
cd integration_environment
vagrant ssh DEBIAN10

cd ~/omi
./test.py  # Will prompt for the distribution, specify as a positional arg to run automatically
```

The `test.py` has the following optional arguments that can be specified:

+ `--docker`: Sets up a docker container for the distribution selected and runs the tests in there
+ `--interactive`: When combined with `--docker` it will open an interactive shell in the test docker container so you can manually run whatever tests you want
+ `--output-script`: Whether to output the test bash script instead of running it
+ `--skip-deps`: Don't install the required test dependencies
+ `--verify-version`: Instead of running the full test suite, this just verifies the library version can be loaded and the versions match the argument value
