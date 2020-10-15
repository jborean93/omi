# Manually Building

If you wish to manually build these libraries and not use the ones in the `PSWSMan` module then you can use this guide.
There are 2 ways that you can build each library

+ Using the python script `build.py`, or
+ Manually running the build steps

## Using build.py

The `build.py` script is designed to handle all the complexities for building both `mi` and `psrpclient` so you don't have to.
It will do the following

+ Install any known depedencies for the distribution selected
+ Set up the build folders for both `mi` and `psrpclient` as required
+ Set the configure and build arguments based on what is required
+ Build the libraries
+ Copy the built libraries into `PSWSMan/lib/{distribution}`

To use `build.py` run `./build.py {distribution}`.
There are some other arguments you can supply to alter the behaviour of the build script like:

+ `--debug`: Generate a debug build of the libraries for later debugging
+ `--docker`: Build the library in a Docker container without polluting your current environment
+ `--output-script`: Whether to output the build bash script instead of running it
+ `--prefix`: Set the OMI install prefix path (default: `/opt/omi`). This is only useful for defining a custom config base path that the library will use
+ `--skip-clear`: Don't clear the `Unix/build-{distribution}` folder before building to speed up compilation after making changes to the code
+ `--skip-deps`: Don't install the required build dependencies

Once the build step is completed it will generate the compiled libraries at `PSWSMan/lib/{distribution}/*`.

The aim is to support the same distributions that PowerShell supports but that is a work in progress.
The distributions that are currently setup in the `build.py` script are:

+ [alpine3.json](../distribution_meta/alpine3.json)
+ [archlinux.json](../distribution_meta/archlinux.json)
+ [centos7.json](../distribution_meta/centos7.json)
+ [centos8.json](../distribution_meta/centos8.json)
+ [debian8.json](../distribution_meta/debian8.json)
+ [debian9.json](../distribution_meta/debian9.json)
+ [debian10.json](../distribution_meta/debian10.json)
+ [fedora31.json](../distribution_meta/fedora31.json)
+ [fedora32.json](../distribution_meta/fedora32.json)
+ [macOS.json](../distribution_meta/macOS.json) - Cannot be built on a Docker container, must be built on an actual macOS host
+ [ubuntu16.04.json](../distribution_meta/ubuntu16.04.json)
+ [ubuntu18.04.json](../distribution_meta/ubuntu18.04.json)

The json file contains all the information required for `build.py` to install the depedencies and build the libraries.

## Manually building

While it is recommended to use `build.py` to do the build for you, you can still compile the libraries manually.
You can have a look at the steps run by `build.py` by running `./build.py {distribution} --output-script`.
There are 2 libraries that are built and used by PowerShell:

+ `mi`
+ `psrpclient`

To build `mi manually you can run:

```bash
cd Unix
./configure --outputdirname=build-distribution --prefix=/opt/omi
make
```

There are other options you can supplied to `configure`, run `./configure --help` to view them.
Once this is finished it will generate a bunch of libraries but the one we are interested in is in `Unix/build-{distribution}/lib/libmi.so`.
You can then use `libmi.so` with PowerShell to enhance your WSMan experience on Linux.

The 2nd library `psrpclient` is a bit more complicated as it must be linked against `mi` and the build script looks for this in certain locations.
There are also a few patches that are manually applied to the source code to either fix bugs in the build process or other things enabled by the `mi` changes.
If you wish to just build it manually you can do the following in a cloned [psl-omi-provider](https://github.com/PowerShell/psl-omi-provider.git) repo:

```bash
cd src
cmake .
make psrpclient
```

The `libpsrpclient.so` library will be created in the same directory as make files.
The build process expects to find the `libmi` libraries at `omi/Unix/output/lib/libmi.so` from the root of the repo.
You can use symlinks like the below to set things up against your own compiled version of `mi`:

```bash
# Commands are run from the root of the psl-omi-provider repository

# Remove the existing git submodule folder
rm -rf omi

# Create a symlink of 'omi' -> '~/dev/omi' where the latter is where the omi repo has been checked out to
ln -s ~/dev/omi omi

# create a symlink called output that points to the build-distribution distribution that we want to link against
ln -s build-distribution omi/Unix/output

# Start the build process
cd src
```

You can see all these steps by running `./build.py --output-script` to get an idea of this in action.
