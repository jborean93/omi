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
+ Copy the built libraries into `build/lib/{distribution}`

To use `build.py` run `./build.py {distribution}`.
There are some other arguments you can supply to alter the behaviour of the build script like:

+ `--debug`: Generate a debug build of the libraries for later debugging
+ `--docker`: Build the library in a Docker container without polluting your current environment
+ `--output-script`: Whether to output the build bash script instead of running it
+ `--prefix`: Set the OMI install prefix path (default: `/opt/omi`). This is only useful for defining a custom config base path that the library will use
+ `--skip-clear`: Don't clear the `Unix/build-{distribution}` folder before building to speed up compilation after making changes to the code
+ `--skip-deps`: Don't install the required build dependencies

Once the build step is completed it will generate the compiled libraries at `build/lib/{distribution}/*`.

The aim is to support the same distributions that PowerShell supports through universal builds that work across a wide range of distributions.
There are currently the following universal builds that are distributed with `PSWSMan`:

+ [glibc-1.0.json](../distribution_meta/glibc-1.0.json)
+ [glibc-1.1.json](../distribution_meta/glibc-1.1.json)
+ [glibc-3.json](../distribution_meta/glibc-3.json)
+ [musl-1.1.json](../distribution_meta/musl-1.1.json)
+ [musl-3.json](../distribution_meta/musl-3.json)
+ [macOS-1.1.json](../distribution_meta/macOS-1.1.json)
+ [macOS-3.json](../distribution_meta/macOS-3.json)

The `glibc` builds are designed for Linux distributions that run on GNU/Linux; CentOS, Ubuntu, Debian, Fedora, RHEL, OpenSUSE, etc.
The `musl` builds are designed for Linux distributions based on Busybox like Alpine.
The `macOS` build cannot be run on Docker but are designed for macOS.
Each build contains a number that relates to the OpenSSL version it is compiled against.
This is important as OpenSSL is not API/ABI compatible across these versions so we need to produce a separate library for each.

There are also the following distribution specific setups that is used for testing these universal builds such as:

+ [alpine3.json](../distribution_meta/alpine3.json)
+ [archlinux.json](../distribution_meta/archlinux.json)
+ [centos7.json](../distribution_meta/centos7.json)
+ [centos8.json](../distribution_meta/centos8.json)
+ [debian9.json](../distribution_meta/debian9.json)
+ [debian10.json](../distribution_meta/debian10.json)
+ [fedora32.json](../distribution_meta/fedora32.json)
+ [fedora33.json](../distribution_meta/fedora33.json)
+ [ubuntu16.04.json](../distribution_meta/ubuntu16.04.json)
+ [ubuntu18.04.json](../distribution_meta/ubuntu18.04.json)
+ [ubuntu20.04.json](../distribution_meta/ubuntu20.04.json)

These can also be used to build `libmi` specifically for that distribution if need be.

## Manually building

While it is recommended to use `build.py` to do the build for you, you can still compile the libraries manually.
You can have a look at the steps run by `build.py` by running `./build.py {distribution} --output-script`.
There are 2 libraries that are built and used by PowerShell:

+ `mi`
+ `psrpclient`

To build `mi` manually you can run:

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
