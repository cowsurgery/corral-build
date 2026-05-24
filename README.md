# Building / Updating FreeNAS Corral

## Build Guide

Detailed instructions for building FreeNAS can be found [here](https://github.com/freenas/freenas-build/wiki/FreeNAS-9.10---10-—-Setting-up-a-FreeNAS-build-environment).

The steps below are the short summary version.

## Requirements

* Operating System
  * FreeBSD 15.0-RELEASE or later (amd64). Earlier versions (11.0+) may work but are untested with this fork.

* Free space
  * ZFS-based system: ~140GB free space (recommended).
  * UFS-based system: ~180GB free space.

* An amd64 capable processor. 32GB of memory, or an equal/greater amount
  of swap space, is also required.

* An internet connection for downloading source and packages.

## Setting Up a FreeBSD 15.0-RELEASE Builder

This section walks through preparing a fresh FreeBSD 15.0-RELEASE (or higher)
system as a build host for FreeNAS Corral.

### 1. Base System Preparation

Ensure your system is up to date:

```sh
freebsd-update fetch install
pkg update && pkg upgrade -y
```

### 2. ZFS Setup (Recommended)

The build system works best on ZFS. If your system is already on a ZFS root
(the default for FreeBSD 15.0 installations), you are ready to go. Verify
with:

```sh
zpool list
zfs list
```

If you want the build to use ZFS for poudriere jails and snapshots (faster
clean builds), export these before building:

```sh
export USE_ZFS=yes
export ZPOOL=zroot          # your pool name
export ZROOTFS=/corral      # ZFS filesystem prefix for build datasets
```

The build system will create datasets like `zroot/corral/jail` and use
snapshots for clean jail rollback between port builds.

### 3. Install Build Dependencies

All commands must be run as `root`.

The automated bootstrap target installs most dependencies:

```sh
make bootstrap-pkgs
```

This installs the following packages (see `Makefile` lines 113-125):

| Package | Port | Purpose |
|---------|------|---------|
| `pixz` | `archivers/pixz` | Parallel XZ compression |
| `python3` | `lang/python3` | Build scripts (Python 3.11+ on FreeBSD 15) |
| `python` | `lang/python` | Python meta-port (points to Python 3 on FreeBSD 15) |
| `poudriere-devel` | `ports-mgmt/poudriere-devel` | Ports package builder |
| `grub2-pcbsd` | `sysutils/grub2-pcbsd` | GRUB bootloader (BIOS) |
| `grub2-efi` | `sysutils/grub2-efi` | GRUB bootloader (UEFI) |
| `xorriso` | `sysutils/xorriso` | ISO image creation |
| `git` | `devel/git` | Source code checkout |
| `gmake` | `devel/gmake` | GNU Make |
| `pigz` | `archivers/pigz` | Parallel gzip compression |

Plus the Python `six` module installed via pip.

#### Resolved Issues for FreeBSD 15.0

The following toolchain and compatibility issues have been fixed across
the `corral-build` and `os` repositories to allow building FreeBSD 11
source on a FreeBSD 15.0 host:

**Bootstrap & Package Fixes (corral-build repo):**

- `archivers/pxz` replaced with `archivers/pixz` (#2)
- `WITHOUT_GROFF=yes` added - C++17 forbids `register` keyword (#4)
- `WITHOUT_LINT=yes` and `LINT=nolint` added - lint removed from FreeBSD (#9, #10)
- `CFLAGS+=-Wno-error=incompatible-pointer-types -Wno-error=int-conversion
  -Wno-error=incompatible-function-pointer-types` - clang 18+ promotes
  these to errors (#8)
- `CFLAGS+=-fcommon` - restores pre-C11 tentative definition behavior
  for FreeBSD 11 source that defines globals in headers (#13)
- Close inherited directory FDs at build startup to prevent
  `jail_attach: Operation not permitted` from FreeBSD-SA-21:05
  security hardening (#14)

**FreeBSD 11 Source Fixes (os repo):**

- `yydebug` undefined in `localedef` - FreeBSD 15's byacc change (#1)
- Lambda parameter shadowing in `CGOpenMPRuntime.cpp` - C++17 rule (#2)
- Non-POSIX regex in magic files (`\s`, `\w`, `\t`, `\r\n`, `` \` ``)
  replaced with POSIX equivalents (#3-#7)
- Missing `sys/auxv.h` header and `elf_aux_info()` function backported
  for FreeBSD 15 host `crunchgen` compatibility (#8, #9)
- `config.h` globals fixed with proper `extern` declarations and named
  struct tags to prevent bus errors (#10-#13)
- Duplicate `yylloc` in `dtc` lexer/parser fixed (#14)
- `[vdso]` filtered from `ldd` output in `installworld` (#15)

#### Remaining Notes

- **`lang/python` (Python 2) is removed.** FreeBSD 15 only ships Python 3.
  The `lang/python` meta-port now points to Python 3.11. The bootstrap step
  `make bootstrap-pkgs` works as-is because `python` resolves to `python3`.

- **Python version for ports.** The build system sets
  `DEFAULT_VERSIONS+=python=3.6` in the ports config (`config.pyd`). This
  applies inside the poudriere jail which uses the 2017Q1 ports tree where
  Python 3.6 is available, so it should not need changing for the host.

- **Jail support required.** The build creates poudriere jails to compile
  ports. The build system automatically closes inherited directory file
  descriptors that would trigger FreeBSD-SA-21:05 security restrictions
  on `jail_attach`. If you still see `jail: jail_attach: Operation not
  permitted`, ensure your host supports `jail(8)` and is not itself
  running inside a restricted jail or container.

If `make bootstrap-pkgs` fails, install the packages manually:

```sh
pkg install -y archivers/pixz lang/python3 ports-mgmt/poudriere-devel \
    sysutils/grub2-pcbsd sysutils/xorriso sysutils/grub2-efi \
    devel/git devel/gmake archivers/pigz
python3 -m ensurepip
python3 -m pip install six
```

### 4. Verify Build Environment

The build system includes a host validation script. Run it manually to check
that all required tools are present:

```sh
make buildenv
# or directly:
python3 build/tools/check-host.py
```

This checks for: `git`, `pxz`/`pixz`, `python3`, `poudriere`, `grub-mkrescue`,
`grub2-efi` (checks for `/usr/local/lib/grub/x86_64-efi/zfs.mod`), `xorriso`,
and `gmake`.

### 5. Clone Path Length Limitation

The build system uses nullfs mounts and requires the full path to the build
root to be **38 characters or fewer**. Clone into a short path:

```sh
# Good:
git clone git@github.com:cowsurgery/corral-build.git /build/corral

# Bad (too long):
git clone git@github.com:cowsurgery/corral-build.git /home/user/projects/freenas/corral-build
```

### 6. Select a Build Profile

Two profiles are available:

| Profile | Branch | Use Case |
|---------|--------|----------|
| `corral` | master | Nightly / development builds |
| `corral-stable` | stable | Stable release builds |

Set your profile:

```sh
echo corral > build/profiles/profile-setting
# or pass PROFILE= on each make invocation
```

## Building FreeNAS

Note: All commands must be run as `root`.

Install the dependencies:

    # make bootstrap-pkgs

Download and assemble the source code (clones ~31 git repositories):

    # make checkout PROFILE=corral

Compile the source, then generate the .ISO:

    # make release PROFILE=corral

The valid profile types are "corral" and "corral-stable" (see
the build/profiles directory) to build a nightly from the master branch or a stable build from the stable branch, respectively.
Instead of specifying PROFILE=profile_type, you can also set the profile type in the file build/profiles/profile-setting
(e.g. ```echo corral > build/profiles/profile-setting```).

Once the build completes successfully, you'll have release bits in the `_BE`
directory.

### Build Output

The build produces artifacts in `_BE/`:

```
_BE/
  objs/
    world/          # Installed FreeBSD world
    jail/           # Poudriere build jail
    ports/          # Built port packages
    packages/       # FreeNAS distribution packages
    iso/            # ISO staging
  release/          # Final ISO and checksums
  os/               # FreeBSD source
  middleware/       # FreeNAS middleware source
  ports/            # Ports tree
  gui/              # GUI source
```

### Build Phases

The `make release` target runs these phases in order:

1. **buildworld** - Compiles FreeBSD 11 world (~27 min, ~350K lines of log)
2. **buildkernel** - Compiles FreeNAS kernel and debug kernel (`FREENAS.amd64`)
3. **portsjail** - Installs world into poudriere jail, runs `ldconfig`
4. **ports** - Builds ~400 port packages via poudriere
5. **world** - Installs world, kernel, ports into final image
6. **packages** - Creates FreeNAS distribution packages (base-os, middleware, etc.)
7. **images** - Generates bootable ISO with GRUB (BIOS + UEFI)

### Troubleshooting

- **Dangling mounts**: If a build crashes, nullfs mounts may be left behind.
  Check with `mount | grep _BE` and clean up with `umount`.
- **Disk space**: Monitor with `df -h` or `zfs list`. A full build needs
  140-180GB.
- **Parallel jobs**: The build auto-detects CPU count and sets
  `MAKE_JOBS = 2 * ncpu + 1`. Override with `MAKE_JOBS=N` if needed.
- **Poudriere failures**: Check logs in `_BE/objs/poudriere/data/logs/bulk/`.

## Updating an existing installation

To update an existing FreeNAS Corral instance that you are using for development
purposes:

* ```make update```
* ```make ports```
* ```make reinstall-package package=freenas host=root@1.2.3.4```

Where 1.2.3.4 is the IP address of your development platform.  SSH will be
used to push and install the new packages onto that host.  (Note previous
comment about setting the profile).  PLEASE NOTE that this is an advanced
development technique and may completely destroy your system if you don't know
what you're doing.

## Architecture Overview

The build system uses a custom Python DSL (`.pyd` files) for configuration.
Key configuration files:

| File | Purpose |
|------|---------|
| `build/config/env.pyd` | Global environment variables and paths |
| `build/profiles/corral/env.pyd` | Profile-specific overrides (FreeBSD version, product version) |
| `build/profiles/corral/repos.pyd` | Git repositories to clone (~31 repos from cowsurgery org) |
| `build/profiles/corral/config.pyd` | Kernel config, make.conf options, customize tasks |
| `build/profiles/corral/ports-system.pyd` | System port packages to build |
| `build/profiles/corral/ports-middleware.pyd` | FreeNAS middleware ports |
| `build/profiles/corral/kernel/FREENAS.amd64` | Custom kernel configuration |
| `build/config/templates/poudriere.conf` | Poudriere configuration template |
