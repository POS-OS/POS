# Building
`./build` (`buildsys/build.sh`) builds the release: every stage in
`stages/`, each assembled into one archive, and the images in `images/`. It
runs on the host or in any toolbox and needs the host's podman, which it
reaches through `flatpak-spawn --host` from inside a toolbox, as the
`toolbox` CLI does. Every step of a build runs in a container of its own
(see "Build containers").

    $ ./build plan                 # what run would build, in order
    $ ./build run                  # build and assemble every stage
    $ ./build run core-libs        # one stage
    $ ./build run zlib             # one package (and what it needs)
    $ ./build prepare              # prepare sources ahead of a run
    $ ./build status
    $ ./build rpm                  # pos, pos-sdk and pos-fedora RPM packages
    $ devtools/install.sh          # install the archives as /pos
    $ devtools/try-rpm.sh          # try out the RPM packages
    $ ./build image container-dnf  # make an image of the current build again
    $ ./build image fedora-toolbox # POS as a toolbox image
    $ ./build reference            # store the build as the reference of later ones
    $ devtools/compare-builds.sh <id> <id>  # what differs between two builds

## Builds
A build has an ID (a timestamp) and keeps everything under
`work/builds/<id>`: `dest/<package>` staging trees, `debug/<package>` debug
info (see "Debug info"), `logs/<package>.log`, the stage archives
`pos-<stage>-<id>.tar.zst` with their `pos-debug-<stage>-<id>.tar.zst`,
the RPM packages in `rpm/`, and the image archives
`pos-image-<image>-<id>.tar.zst`. `work/builds/current`
points at the build that `run` continues. `run --new` starts another. A
package is built once per build; `./build rebuild <package>` drops it
from the current build so the next `run` builds it again. Packages that were
built against it are not rebuilt. Builds from before build containers
(their `info` has no `tools-image`) cannot be continued; `status`, `rpm`,
`image` and `reference` still work on them.

## Settings
Settings of `./build` are lines of `<key> <value>` in
`~/.config/pos/build.conf`, or in the file `POS_BUILD_CONFIG` names.
`build.conf.dist` lists them; copy it there and edit. Each setting's
environment variable overrides the file, for a single run. Only a new
build reads them: what it uses is recorded in its `info`, so a build
keeps its settings when the file changes. The file is read as data, and
an unknown key is an error.

| key | variable | default |
| --- | --- | --- |
| `fedora-release` | `POS_FEDORA_RELEASE` | 44 |
| `tools-image` | `POS_TOOLS_IMAGE` | `registry.fedoraproject.org/fedora:<release>` |
| `reference-dir` | `POS_REFERENCE_DIR` | none: no reference store |
| `reference` | `POS_REFERENCE` | the store's default (see "Reference builds"); `none` builds from nothing |

## Sources
POS builds from upstream source, not from upstream releases, so it does
the release preparation itself. A source goes through three steps:

1. Sync: `src/<source>` holds exactly the files upstream's git tracks, and
   `src/<source>.upstream` records the branch (`ref`), `commit`, commit
   `date` and `url` it came from. Both are committed.
2. Prepare: what upstream's release process adds to a release tarball.
   `packages/<source>/prepare.sh` works on a copy of the committed
   `src/<source>`, with helpers from `buildsys/prepare.sh`: `prep_pull` runs
   gnulib bootstrap's pull phase or `autopull.sh` (translations, submodule
   hooks), `prep_gen` generates the build system, `prep_version` writes
   `.tarball-version`. Files gnulib-tool links to `src/gnulib` are copied,
   so the prepared tree stands alone. Prepare runs in a build container
   with network access, which has the recipes, the committed source,
   `src/gnulib` and the tree to prepare; `prepare-requires` in the meta
   lists its Fedora packages.
3. Build: from the prepared tree when the source has a prepare recipe, from
   `src/<source>` otherwise. A build needs no network.

Everything that changes or generates source files belongs to prepare:
autogen.sh, bootstrap and autoreconf, generators such as less's
`Makefile.aut`, and edits to upstream files (systemd's libseccomp version
check, shadow's `chsh.c`). A build recipe configures, compiles and installs
a tree it does not change. Sources that need none of that (glibc, gcc,
zlib, the meson and cmake packages, and bash, sqlite and sudo, which commit
their `configure`) have no prepare recipe and are built from `src/`.

Prepared trees are kept in `work/sources/<source>/<key>`. The key is a hash
of the committed source tree, its `.upstream`, the prepare recipe, the
helpers, the `prepare-requires`, and the committed `src/gnulib` for
packages that use gnulib. A tree is prepared once for each key and shared by
every package built from that source (gcc, gcc-bootstrap,
gcc-runtime-bootstrap) and by later builds. `run` prepares a source when it
first needs it; `./build prepare` does it ahead of time. Builds and
prepare use the committed state of a source, so uncommitted changes under
`src/<source>` stop them.

The version prepare gives packages that take theirs from gnulib's
git-version-gen (coreutils, findutils, grep, gzip, sed, diffutils, patch)
is a snapshot name, not a release number: `<ref>-<commit date>-<commit>`,
for example `master-20260924-5eff02ecb19b` (`prep_version`). Other packages
keep the version their own source states. util-linux and logrotate carry
older copies of git-version-gen that accept only a version starting with a
digit; util-linux takes its version from `NEWS`. libseccomp's `main`
says `0.0.0` in `configure.ac` until a release sets it; its prepare
recipe sets the newest release in `CHANGELOG`, which is also the library's
soname (`libseccomp.so.2`) and `SCMP_VER_*`.

Each package's metadata records the source it was built from:
`build-source <source> <key>`, the prepared tree's key or the committed
tree's hash.

## Source archives
`./build run --new --source-archives` creates a build that, after
assembling the stages, archives every source its packages were built from,
as recorded in their metadata: `pos-src-<source>-<key>.tar.zst`, the
prepared tree or the committed tree. It also archives the build recipes as
they are at `HEAD` (`buildsys`, `packages`, `stages`, `images`, `rpm`, the docs) as
`pos-recipes-<id>.tar.zst`, with a warning if they changed since the build
started. Together they are the source of the build's archives. Whether a
build writes them is chosen when it is created.

## Packages
`packages/<name>/` holds `build.sh`, the recipe, and `meta`, which declares
what the package needs and what it gives (format in `buildsys/resolve.sh`):

    build-requires gcc pos-link
    requires glibc zlib
    provides zstd-bootstrap
    obsoletes zstd-bootstrap
    host-requires meson ninja-build

`requires` are run-time requirements, installed along with the package
wherever it is installed. `build-requires` are needed only to build it.
Every package provides its own name. When two available packages provide
what is required, the one the other obsoletes is not used. `host-requires`
are Fedora packages, in the build's tools image (see "Build containers");
`packages/host-base` lists the tools every build gets.

`run` picks a package whose requirements are all available (built in this
build, host packages, or from the reference build), builds it, and repeats
until the targets are built. Where several are ready, a package obsoleted
by another ready one waits. A build does not see the whole build history:
its `/pos` holds exactly the package's requirements, plus the run-time
requirements of those.

## Outputs
One build can produce several packages, as an rpm spec has sub-packages.
The main package lists them (`outputs gcc-runtime`); each has its own
`packages/<name>/meta` with `kind output` and `output-of`, and no
`build.sh`. After the build, an output is a package like any other: its
own `dest/<name>`, requirements, provides, obsoletes and metadata, and a
stage lists it on its own. Wanting an output builds its main package;
`rebuild` of the main package drops its outputs too.

The recipe installs each output into `$(pkg_output <name>)`. `pkg_finish`
then removes from the main package every file an output holds, so each file
belongs to one package and the recipe can install everything first.
Requirements an output provides are not part of its own build's
environment: gcc requires gcc-runtime, which it produces.

## Bootstrap packages
There are three compilers, each a capability:

| capability | compiler | provided by |
| --- | --- | --- |
| `host-gcc` | Fedora's | `host-toolchain` (host package) |
| `gcc-bootstrap` | a POS compiler in `/pos` | `gcc-bootstrap`, `gcc` |
| `gcc` | the self-built sdk compiler | `gcc` |

`gcc-bootstrap` is gcc built by `host-gcc` against bootstrap packages:
glibc, libstdc++, gmp, mpfr, mpc, zlib and zstd, which it runs on, and
binutils, which it execs. Each `<name>-bootstrap` is built by `host-gcc`.

`gcc-bootstrap` then builds the main packages of those same libraries. Each
main package provides its bootstrap name as well and obsoletes the
bootstrap package, so once it is built it replaces the bootstrap package
everywhere, including under `gcc-bootstrap` itself. With all of them built,
`gcc-bootstrap` builds `gcc` against them. `gcc` requires and provides
`gcc-bootstrap` and obsoletes the `gcc-bootstrap` package.

Every other package requires `gcc`, so it is built by the self-built
compiler. The libraries `gcc` runs on cannot require `gcc`; they require
`gcc-bootstrap`, which is the `gcc-bootstrap` package the first time.
It is built from the same sources, so it generates the same code `gcc`
would. Release stages list only main packages; the sdk ships `gcc`.

The bootstrap packages are built by a build without a reference build
(from nothing). With one, the reference's packages stand in for them
(see "Reference builds"), and the chain starts at the main packages.

The same arrangement breaks other cycles. `util-linux-bootstrap` is
util-linux without libsystemd; systemd requires it, and util-linux requires
systemd.

A bootstrap package's `build.sh` sources the main recipe. Where the builds
differ, it sets `configure_extra` first; the main recipe appends that to its
configure arguments, where the later flag wins (gmp-bootstrap
`--disable-cxx`, util-linux-bootstrap `--without-systemd`).

## Build containers
Every step of a build (preparing a source, building a package, making the
RPM packages and the images made with dnf) runs in a podman container of
its own. A package build sees two things:

* `/usr`: the build's tools image, `localhost/pos-tools:<id>`, made when the
  build is created (`buildsys/tools.containerfile`). It is the `tools-image`
  setting, Fedora's container image by default, pulled then and pinned by
  digest (`info`: `tools-base`), with the `host-requires` and
  `prepare-requires` of every package and `rpm-build` installed by dnf.
  Nothing installs while a build runs, so every step of a run sees the
  same tools whatever order they run in. When a package declares more
  later in the build, the image is made again on the same base
  (`tools-packages` lists what it has). What a step uses from Fedora must
  be declared (`host-base` for every build): the base image has little
  more than bash, coreutils and dnf.
* `/pos`: the package's resolved environment, composed for this build: the
  staging trees of the POS packages in it (this build's `dest/<name>`, or
  the reference's), hard-linked into `roots/<package>`, mounted read-only.
  A path has one owner: composing fails when two packages of the
  environment ship the same file or link. The root is removed after the
  build, and kept when it fails, to look at.

A requirement the package does not declare is not there, so the build
fails instead of picking it up from whatever else is installed. Of the
checkout, a step sees only what it uses, at the host's paths: a package
build the recipes (`buildsys`, `packages`) and its source tree read-only,
and the build's `build`, `dest` and `debug` directories. A step runs as the
caller, with `HOME=/tmp`, `LC_ALL=C` and no network. Preparing and making
the RPM packages have network (for `pos-fedora`'s Fedora provides), and
images made with dnf run as the container's root (the caller outside it)
with network.

A built package's staging tree carries its metadata in
`/pos/lib/pos/packages/<name>/`: `meta` (the package's meta, the build
ID, the packages it was built against, the tools image ID and the
reference build) and `files`. The metadata stays in the stage archives, so
an installed `/pos` records what it contains.

`./build clean` removes the tools image; a later `run` makes it again.

## Reference builds
A build takes what it does not build from a reference build: a complete
earlier build. Its packages are available to the resolver as
`<name>@ref`: where no package of the build provides a capability, the
reference's copy does, if the capability is a bootstrap one (one that a
package another obsoletes provides) or if no target of the run provides it.
So the reference's gcc stands in for gcc-bootstrap and no bootstrap package
is built; a full build builds glibc and the libraries gcc runs on with the
reference's gcc, then gcc, then the rest with it. A run of a single
package builds only that package, against the reference.

A reference package's own requirements are those it was built with (its
recorded meta). They are met by this build's packages once built,
otherwise by the reference's, targets or not: the reference's gcc requires
glibc, and builds it. Until gmp, mpfr and mpc are built, their builds see
the reference's copies, which the reference's gcc runs on.

`./build reference [<id>]` (default: the current build) stores a complete
build in the reference store, the `reference-dir` setting, as
`pos-ref-<id>.tar.zst`: its `info` and the staging trees of its packages,
but for the bootstrap packages. It marks the build the store's `default`,
the reference of new builds. A build records its reference in `info`
(`reference`) and restores it from the store into `work/references/<id>`
when it is not there. The store is a directory outside the checkout, so
removing builds never removes a reference.

With no reference store, or `reference none`, a build starts from nothing:
the bootstrap packages, built with Fedora's compiler (see "Bootstrap
packages"). Comparing such a build with one made against a reference
(`devtools/compare-builds.sh`: the files of each package and the libraries
every ELF file links against) shows what a build environment leaked into
a package.

## Build setup
`pkg_setup` has no build strategy of its own. A package that changes how
others are built has an `env.sh`, and `pkg_setup` sources the `env.sh` of
every package in the resolved requirements. What a build gets therefore
follows from what it requires, never from what is found on disk:

* `host-toolchain/env.sh`: the Fedora compiler.
* `gcc/env.sh`: a POS compiler, `/pos/bin/gcc`, `g++` and `ld`.
  `gcc-bootstrap/env.sh` sources it; both install to the same paths.
* `pos-link/env.sh`: link against `/pos` with a POS compiler.
* `pos-link-host/env.sh`: link against `/pos` with the Fedora compiler.
  Sources `pos-link/env.sh` and puts `/pos` ahead of `/usr`.

`pos-link` and `pos-link-host` are profiles (`kind profile`): nothing is
built or installed, they only carry the setup and its requirements
(`gcc-bootstrap`, or `host-gcc` and `glibc-bootstrap`). Recipes
build-require one of them, and packages built by the sdk compiler also require
`gcc`. glibc, glibc-bootstrap and gcc-runtime-bootstrap require only
the compiler (see "Core libs stage").

Requirements are what a build sees, but configure scripts also find what
they were not asked to. gcc's run-time requirements are in every build
that uses it, so an undeclared check for zlib or zstd finds the bootstrap
copy. A package that links a library must require it.

## Build flags
`pkg_setup` sets the flags every package is built with (`pkg_flags`), as
Fedora's and Arch's package builds do, before the `env.sh` files add to
them:

* `CFLAGS`: `-O2 -g -pipe`, and the hardening `-fexceptions
  -Wp,-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fcf-protection`, with
  frame pointers (`-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer`)
  for profilers. `CXXFLAGS` adds `-D_GLIBCXX_ASSERTIONS`.
* `LDFLAGS`: `-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now
  -Wl,--build-id=sha1`.
* PIE and `-fstack-protector-strong` are the POS compiler's defaults
  (`--enable-default-pie --enable-default-ssp`), and it gives every link
  a build ID (`--enable-linker-build-id`). Fedora's compiler, used for the
  bootstrap packages, does both through its own defaults.

meson builds use `--buildtype=plain` and cmake builds
`-DCMAKE_BUILD_TYPE=None`, so these flags are the only ones; meson's
`release` would have added `-O3` and no debug info. Warnings are not made
errors (no `-Werror=format-security`): POS builds upstream's development
branches.

glibc and the gcc builds (gcc, gcc-bootstrap, gcc-runtime-bootstrap) keep
only `-O2 -g -pipe` (`pos_optflags`). glibc has its own hardening options
and builds parts of itself without the stack protector; gcc derives the
flags of its target libraries (libgcc, libstdc++) from `CFLAGS`. glibc
also gets no `LDFLAGS`; it links itself by its own rules.

CET (`-fcf-protection`) only takes effect when every object of a link
has it, including glibc's `crt1.o` and `crti.o` and gcc's `crtbegin*.o`.
glibc is configured `--enable-cet` (its default follows the compiler's,
which is off); gcc enables it in its target libraries by itself.

## Debug info
`pkg_finish` strips what a package installs and keeps the debug info
separately (`pkg_strip`), as Fedora's debuginfo packages do. Each ELF
program and shared library's debug info is copied to
`work/builds/<id>/debug/<package>/pos/lib/debug/.build-id/<xx>/<rest>.debug`,
named by its build ID, where gdb and debuginfod look for it; the file in
`dest/<package>` is then stripped. The loader keeps its symbol table
(valgrind needs it), static libraries lose only their debug info, and
object files (`crt*.o`) are left as they are. A file without a build ID is
stripped with a warning in the log. Set-uid bits, modes and hard links are
kept.

The debug trees are not part of build roots. Each stage's is
archived next to it as `pos-debug-<stage>-<id>.tar.zst`, which extracts
on top of the stage into `/pos/lib/debug`, and `./build rpm` makes it the
`pos-debuginfo` package. gdb looks in `/usr/lib/debug` unless told
otherwise, and reads the directory before it loads the program:

    $ gdb -iex 'set debug-file-directory /usr/lib/debug:/pos/lib/debug' /pos/bin/bash

# Prefix
`/pos` is the prefix for everything POS ships: the base system, and optional
components such as the SDK. It stays read-only for the whole lifetime of an
installation. An update replaces the tree. Programs, libraries, headers, and
shipped data that POS provides install there. Programs in `/pos` have no
dependencies outside the prefix.

Third-party applications install in separate hierarchy. A machine can keep `/usr` for that, or any other prefix.

Configuration and mutable data stay outside the prefix:

* `/etc` is local configuration.
* `/var` is variable data.
* `/run` is runtime state.

Every package is configured with `--sysconfdir=/etc` and, where it applies,
`--localstatedir=/var` (`$sysconfdir` and `$localstatedir` in `buildsys/pkg.sh`).
There is no `/pos/etc` or `/pos/var`. glibc only rewrites those paths to
`/etc` and `/var` when its prefix is `/usr`, so with `--prefix=/pos` the
flags have to be passed explicitly. Files a package installs into `etc/` or
`var/` at build time are shipped defaults, so `pkg_finish` moves them to
`/pos/share/factory`. That is the tree `systemd-tmpfiles` `C` lines copy
into place when a file is missing. glibc's nss_db helper is one of them: it
is installed as `/var/db/Makefile` and generates the `.db` files there from
`/etc`. Packages that have a separate vendor directory (pam's `vendordir`)
ship their defaults there instead. `DESTDIR` is only the staging directory
under `work/` used at install time. It is not part of the running system.

Packages assume `/usr` in places `--prefix` does not reach. Two ways to
handle it: a configure option that moves the path (preferred, it keeps the
binary self-contained), or a symlink from the hardcoded path back into
`/pos`. Symlinks live in the root filesystem, outside any package, so they
are part of the root layout an image stage creates; a package never installs
outside `/pos` (`buildsys/build.sh` warns on it).

* systemd: units, generators and `systemd-*` binaries are searched relative
  to `--prefix`. The programs it execs default to `/usr/bin` and `/usr/sbin`
  and are moved with the `*-path` options (`-Dkmod-path=/pos/bin/kmod`,
  `-Dmount-path`, `-Dsulogin-path`, ...). Its `pam.d` files go to
  `-Dpamconfdir=/pos/share/pam/pam.d`, the vendor directory POS pam reads;
  pam's other fallback, `/usr/lib/pam.d`, is hardcoded.
* systemd-tmpfiles: a `C` line without a source argument copies from
  `/usr/share/factory/`. That path is hardcoded. Either POS tmpfiles lines
  give the source explicitly (`C /etc/foo - - - - /pos/share/factory/etc/foo`),
  or the root layout has `/usr/share/factory -> /pos/share/factory`. The
  symlink also makes third-party tmpfiles lines work unchanged.
* Shebangs and the kernel: `#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env`,
  `/sbin/init`, and `/lib64/ld-linux-x86-64.so.2` for third-party binaries
  are the same class. Which of these the root layout provides as symlinks
  into `/pos` is decided per image (see "Images"), and for a machine it
  interacts with keeping its own `/usr`. The container image has them all.
* kmod: `-Ddistconfdir=/pos/lib` for `modprobe.d`/`depmod.d`;
  `-Dmoduledir=/pos/lib/modules`.
* util-linux: `--enable-fs-paths-default=/pos/sbin` for mount helpers.
* shadow: `--enable-vendordir=/pos/share/factory/etc`, so login.defs is found
  before `/etc/login.defs` has been created. pam's vendordir
  (`/pos/share/pam`) could move to the same tree for consistency.
* logrotate: `--with-compress-command=/pos/bin/gzip`. Tool paths found by
  configure are the general case: a build container finds `/usr/bin`
  tools and records those unless told otherwise (man-db's recipe shows the
  `--with-nroff=/pos/bin/nroff` pattern).
* systemd unit, tmpfiles and sysusers directories for packages built before
  systemd (util-linux): given explicitly as `/pos/lib/systemd/system`,
  `/pos/lib/tmpfiles.d`, `/pos/lib/sysusers.d`.

## Library directory
`/pos/lib` is the only library directory: the native x86-64 libraries, the
loader `/pos/lib/ld-linux-x86-64.so.2`, and the architecture-independent
trees (`lib/systemd`, `lib/modules`, `lib/pos`). There is no `/pos/lib64`
and no multilib. This is the Arch and LFS layout, not Fedora's, where
`lib64` holds the 64-bit libraries and `lib` the 32-bit ones and the
architecture-independent files.

The upstream defaults assume Fedora's layout in a few places, which the
recipes override:

* gcc: `t-linux64` names `../lib64` for `-m64`; `gcc_pos_patch_defaults`
  makes it `../lib`, and gcc is `--disable-multilib`.
* glibc: the x86-64 `ldd-rewrite.sed` turns the loader list into the
  `lib64`/`lib`/`libx32` set; `ldd-rewrite-script = no` in configparms keeps
  `RTLDLIST` at the installed loader.
* meson, cmake's GNUInstallDirs and Fedora's gcc see the build
  container's `/usr/lib64` and choose `lib64`; recipes built with them set libdir to
  `/pos/lib`. gcc-bootstrap, built by Fedora's g++, is `--disable-libcc1`:
  libcc1 installs into the building compiler's multilib directory.

`pkg_record` stops a build that installs into `pos/lib64`, `pos/lib32` or
`pos/libx32`; the POS loader would not find libraries there.

32-bit binaries are not built. 32-bit programs are applications 
(Steam, older Wine), outside the base system,
and can run from an install root of another distribution that ships
32-bit libraries. If POS ever ships an i686 compat set, it goes in
`/pos/lib32` with its loader at `/pos/lib32/ld-linux.so.2`; gcc then
gets multilib with `m64=../lib m32=../lib32`, and the glibc recipe writes
ldd's `RTLDLIST` itself.

# Set-uid programs
The staging install runs unprivileged, so `make install` cannot chown or set
set-uid bits (util-linux `--disable-makeinstall-chown --disable-makeinstall-setuid`,
sudo `install_uid=$(id -u)`). Recipes call `pkg_setuid` on the programs that
need it (su, mount, umount, chfn, chsh, passwd, chage, gpasswd, newgrp,
sudo, crontab, dbus-daemon-launch-helper); that sets mode 4755 in
the staging tree. `assemble.sh` records owner 0:0 in the archive, so
extracting it as root produces root-owned set-uid files. Anything that
installs the tree has to preserve modes (`tar -x` as root, or `cp -a`, not
`cp -r`; unprivileged `tar -x` needs `-p`).

# Core libs stage
Each package stages into `work/builds/<id>/dest/<name>` with `--prefix=/pos`.

With the sdk compiler, packages use `/pos/bin/gcc`, `/pos/bin/g++`, and
`/pos/bin/ld`, whose defaults already search `/pos/include` and `/pos/lib`,
and `pos-link` adds only
`-L/pos/lib` and `PKG_CONFIG_LIBDIR`. No rpath: the POS loader finds
`/pos/lib` through its own cache or its default search path (below).
`/pos/include` must not be named again with `-isystem` or
`CPLUS_INCLUDE_PATH`. That moves it in front of the libstdc++ directories,
gcc drops the later duplicate, and libstdc++'s `#include_next <stdlib.h>`
finds nothing after itself (ncurses then falls back to `<iostream.h>`).

The bootstrap packages are built by the host toolchain. Only for those
does `pos-link-host` add `-isystem /pos/include`,
`C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, and `LIBRARY_PATH` to put `/pos`
ahead of the host's `/usr`.

The POS loader and ldconfig use `/etc/pos/ld.so.cache` and
`/etc/pos/ld.so.conf`, not `/etc/ld.so.cache` and `/etc/ld.so.conf`. Those
belong to the loader of whatever else is on the machine: a `/usr` the
machine keeps, or Fedora in a build container. One cache listing both sets of
libraries makes each loader pick up the other's libc; in a toolbox the POS
loader found Fedora's `/lib64/libc.so.6` and every program without an rpath
crashed (gcc's libatomic configure runs one). The glibc recipe sets
`LD_SO_CACHE` and `LD_SO_CONF` in `configparms`. With no POS cache, as in a
build container, the loader searches `/pos/lib`.

Binaries carry no rpath. The loader searches the binary's RPATH/RUNPATH,
then `LD_LIBRARY_PATH`, then its cache, then its default directory
(`/pos/lib`). The POS cache is built from `/pos/lib` and
`/etc/pos/ld.so.conf`, so it gives the same answer as the default; an rpath
would only repeat it. Library lookup is decided in one place: the cache and
`/etc/pos/ld.so.conf`.

glibc is built with gcc-bootstrap, which runs on glibc-bootstrap. This is the same arrangement
as Fedora: the gcc in `/usr` was linked against the installed libc, and it
compiles the glibc that will replace it. The compiler runs on the old libc.
The new one is a build output. glibc passes `-nostdlib -nostartfiles` and
names the build-tree `libc.so` and `ld.so` on the link line, then appends
its own `-Wl,-dynamic-linker=/pos/lib/ld-linux-x86-64.so.2`.

The extra search path other packages get stays off for this build: glibc
requires `gcc`, not `pos-link`.
`C_INCLUDE_PATH` and `LIBRARY_PATH` are not disabled by `-nostdinc` or
`-nostdlib`, and the `/pos` link flags are not ones glibc puts on its own
binaries. Fedora gets the header isolation from `--with-headers`, which
turns on `-nostdinc` and adds only the kernel headers. Our recipe does not
pass that, because the kernel headers and the installed glibc headers share
`/pos/include`.

gcc-runtime-bootstrap skips the same search path. Its libgcc and libstdc++
are built by the in-tree xgcc, which reads `LIBRARY_PATH` and would pick up
the copies already installed in `/pos`.

For the bootstrap packages, the host gcc is still
visible and keeps `/usr/include` and `/usr/lib64` in its default search
after `/pos`. A configure check for a library that is not in `/pos` yet
then finds the tools image's copy, and the binary fails to load because the
POS loader searches only `/pos/lib`. A build that dies with exit 127 while
running its own freshly built program is this. Check with
`objdump -p <binary> | grep NEEDED`.

glibc installs one compiled locale, C.UTF-8, as
`/pos/lib/locale/C.utf8` (Fedora's glibc-minimal-langpack has the same).
Programs that need a UTF-8 locale fall back to it (tmux), and containers
set it. glibc reads compiled locales only from its own prefix; other
languages would be built the same way (`SUPPORTED-LOCALES`).

gmp and mpfr are in this stage. coreutils `expr` and `factor`, and gawk
`-M`, link them at run time. gmp `--enable-cxx` needs libstdc++. gcc runs on
gmp, so gmp is built before gcc and its gcc-runtime output, and requires
`gcc-runtime-bootstrap`; in the release gcc-runtime provides that name.
gmp-bootstrap, for the compiler, is built `--disable-cxx`.

`run` assembles each stage it was given into one archive,
`work/builds/<id>/pos-<stage>-<id>.tar.zst`, with a top-level `pos/`
directory. The merged tree is left at `work/builds/<id>/assemble/<stage>/pos`.

# Images
An image is a root filesystem with POS installed, archived as
`work/builds/<id>/pos-image-<image>-<id>.tar.zst` by `buildsys/image.sh`.
`images/<image>/layout` names the stages it holds and the root layout
around `/pos`: directories with their modes, and the symlinks into `/pos`
for the paths in "Prefix". `run` makes an image when it assembles every
stage the image holds, so a plain `run` makes them all. The tree is left at
`work/builds/<id>/image/<image>`.

The image extracts its stage archives into `/pos`, then fills what a first
boot would: `/pos/share/factory/etc` and `var` are copied to `/etc` and
`/var`, and `/etc/passwd`, `group`, `shadow` and `gshadow` are created by
POS `systemd-sysusers --root` from `/pos/lib/sysusers.d`. That runs
through the image's own loader, `pos/lib/ld-linux-x86-64.so.2
--library-path ...`, so `/pos` need not be installed where `run` runs.
systemd searches `/usr/lib/sysusers.d`, not `/pos/lib/sysusers.d` (its
`CONF_PATHS` are fixed paths), so the files are named on the command line.
Everything is owned by root in the archive. Group write, which build trees
pick up from the build directory, is removed except on sticky directories.

`images/container` is core-libs, system and the sdk, for
`podman import` or `docker import`. It has no `/etc/pos/ld.so.cache`; the
loader searches `/pos/lib`. Programs are in `/pos/bin` and `/pos/sbin`,
which are not in a container engine's default `PATH`, so the import sets
it:

    $ podman import \
        --change 'ENV PATH=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin' \
        --change 'CMD ["/bin/bash"]' \
        work/builds/<id>/pos-image-container-<id>.tar.zst pos:<id>

`devtools/import-image.sh [-i <image>] [<id>]` does that.

## Images made with dnf
An image with `images/<image>/packages` instead of a layout is made by
`buildsys/image-dnf.sh` with `dnf --installroot`: POS as the base of an RPM
system (see "RPM packages"). Its packages are the build's own RPM files
for `pos`, `pos-sdk`, `pos-fedora` and `pos-debuginfo`, and Fedora
packages from Fedora's repositories, so making it needs the network. `run` makes such
images when it assembles all stages, after making the RPM packages;
`./build image [<image>...]` makes images of the
current build again. Next to the archive, `pos-image-<image>-<id>.packages`
lists the packages installed. The tree is removed after archiving: its
files belong to users the packages create, which only the container's
root can remove.

The root layout comes from Fedora's `filesystem` and `setup` packages and
pos-fedora's links; users and groups are created by rpm from the packages'
sysusers definitions. No package creates `/tmp` and `/dev` (on Fedora,
systemd-tmpfiles and the image builders do), so image-dnf.sh makes them.
`/etc/os-release` is Fedora's.

`images/container-dnf` is `pos`, `pos-sdk`, `pos-fedora` and `dnf`: a
container with POS as its base in which `dnf install` adds Fedora
packages, which use POS for what it replaces:

    $ devtools/import-image.sh -i container-dnf
    $ podman run --rm -it pos-dnf
    # dnf install htop

## Images made with podman
An image with `images/<image>/containerfile` is made by podman from
another image of the build, named in `images/<image>/from`, which `run`
has just made or `./build image` finds in the build. The build imports
that image's archive into podman as `localhost/pos-<x>:<id>` (images
`container-<x>` and `<x>`; `container` is `pos`) and builds on it, as
`BASE`. The result exists only in podman's local store, tagged with the
build ID and with the Fedora release.

`images/fedora-toolbox` is container-dnf as a toolbox image,
`localhost/pos-fedora-toolbox`, for working in a POS-based toolbox; builds
do not use it. It adds what toolbox needs and nothing installs:
toolbox puts its user in `wheel` with an empty password and runs sudo, so
the image has `/etc/sudoers` (POS's, from `/pos/share/factory`), a
`wheel` rule and a PAM configuration for sudo. POS has none for sudo,
and pos-fedora stands in for Fedora's sudo and pam packages, which ship
them.

# RPM packages (experimental)
`./build rpm [<stage>...]` makes the RPM packages of the current build's
assembled stages (default: all), in a build container
(`buildsys/rpm.sh`). They are versioned with the build ID and written to
`work/builds/<id>/rpm`. `run` makes them too
when it makes an image with dnf (see "Images made with dnf"). dnf
installs them as files, next to packages from Fedora's repositories:

    $ sudo dnf --installroot=<root> --releasever=44 --use-host-config \
        install work/builds/<id>/rpm/pos{,-sdk,-fedora}-<id>-1.x86_64.rpm dnf

* `pos` is the `/pos` tree of the stages other than sdk: the OS, as one
  package. It installs nothing outside `/pos` and provides nothing Fedora
  packages require, so it installs on any Fedora system without touching
  it, and is removed again with dnf.
* `pos-sdk` is the `/pos` tree of the sdk stage, and requires `pos` of the
  same build.
* `pos-debuginfo` is the debug info of both in `/pos/lib/debug` (see
  "Debug info"); made when the build has any.
* `pos-fedora` makes a Fedora hybrid: it requires `pos` and `pos-sdk`
  (the systems it is for build with POS) and stands in for the Fedora
  packages POS replaces. On a system built with it, dnf resolves Fedora
  packages against POS and installs only what POS does not have.

`devtools/try-rpm.sh` tries them out in a throwaway toolbox: `pos` next to
Fedora, or a root with POS as its base and Fedora packages on top, run
with podman:

    $ devtools/try-rpm.sh root vim-minimal curl
    $ devtools/try-rpm.sh run ldd /usr/bin/curl
    $ devtools/try-rpm.sh clean

`rpm/fedora` lists the Fedora packages POS replaces, by POS package; a
line counts when its POS package is in the stages. For those, pos-fedora:

* provides what they provide, as Fedora's repositories list it, at
  Fedora's versions: names, `name(x86-64)`, `config()`, `rtld(GNU_HASH)`,
  `user()` and `group()`. rpm creates their system users from the last
  ones when pos-fedora is installed. Their sonames and paths are not copied.
* provides the sonames and symbol versions of the POS libraries, made by
  rpm's own generator from the POS files, so a Fedora binary that needs a
  version POS does not have stays unresolved instead of failing to load.
* conflicts with them, so dnf picks pos-fedora for their names and an
  existing Fedora system is not changed by accident. pos-fedora is for
  building a system, not for converting one.
* links the POS programs into `/usr/bin` (Fedora's `/usr/sbin` and `/bin`
  are links to it) and the libraries and the loader into `/usr/lib64`, and
  provides the `/bin`, `/sbin`, `/usr/sbin` and `/lib64` names of them.
  Fedora binaries request `/lib64/ld-linux-x86-64.so.2`, so they run on
  POS glibc. A path that only Fedora packages pos-fedora does not replace
  have is not linked, so those install next to it.

A claim stands only if POS has every versioned soname and symbol version
the Fedora package provides; otherwise `rpm` drops it with a warning
(listed in `rpm/pos-fedora.unmet`). Packages whose ABI differs from Fedora's
are left out of `rpm/fedora` with the reason, and Fedora's copy is
installed next to POS where something needs it (OpenSSL 3 beside POS
OpenSSL 4).

Fedora packages installed next to POS put their libraries in `/usr/lib64`,
which the POS loader does not search by default. pos-fedora ships
`/etc/pos/ld.so.conf` (`/pos/lib`, then `/usr/lib64`) and runs
`/pos/sbin/ldconfig` after every package that adds libraries there or in
`/pos/lib`, so a later package's scriptlets find them.

rpmbuild's defaults are for Fedora's `/usr`, and both specs turn them off:
automatic dependencies (they would make `pos` provide `libc.so.6()(64bit)`
and replace Fedora without pos-fedora), and the post-install steps
(stripping, debug info, `/usr/lib/.build-id` links, man page compression,
shebang rewriting; the build strips and keeps debug info itself, see
"Debug info"). Modes come from the staging trees, with group write
removed as in images; set-uid bits are kept. `License` is `NOASSERTION`:
package metadata records no license yet. No source RPMs are made;
`--source-archives` covers the sources.

Not covered yet: POS systemd reads units from `/pos/lib/systemd`, not the
`/usr/lib/systemd` Fedora packages install into, and the POS compiler does
not search `/usr/include`, so Fedora `-devel` packages and the compiler are
not replaced.

# SDK
`stages/sdk` is the compiler, the assembler and linker, and the kernel UAPI
headers (linux-headers, binutils, mpc, gcc), plus developer tools moved out
of the system stage (diffutils, patch, man-pages). gmp and mpfr are
core-libs; mpc is only needed to build gcc. The sdk is a component POS
ships, so it installs under `/pos` like the base system. A base system
image does not include it; the builds of other packages require it.
The headers are needed only while compiling: glibc's `errno.h` includes
`<linux/errno.h>`, and nothing loads them at run time.

linux-headers is built from `src/linux`, mainline's `master`, synced as the
subset of the kernel tree that `make headers_install` needs: the top-level
`Makefile`, `scripts/`, `include/uapi/`, x86's `Makefile`, `include/uapi/`
and system call tables, and the licenses. The subset was checked by
comparing its installed headers with those of the whole tree. The recipe
builds out of tree (`O=`), so the source stays as committed. UAPI headers
are compatible with older kernels, so headers from mainline work on the
kernel a machine runs.

binutils is what makes the sdk compiler self-contained. gcc execs `as` and
`ld`; without POS copies it would run the build container's, whose ld
searches `/usr/lib64` on its own. binutils is configured
`--with-lib-path=/pos/lib` so ld searches only `/pos/lib`, and gcc is given
`--with-as=/pos/bin/as --with-ld=/pos/bin/ld`.

The compiler's own programs (cc1, cc1plus, lto1) are ordinary `/pos`
binaries, built without gcc's own staged bootstrap (`--disable-bootstrap`)
with the usual `/pos` link flags, running under the POS loader against
`/pos` glibc and `libstdc++.so.6`. gcc-bootstrap is built by the host g++
against the bootstrap packages; host g++ 16 linking the libstdc++ built
from gcc 17 sources is the compatible direction. gcc is built by
gcc-bootstrap against the main packages. gcc's
top-level configure derives `CFLAGS_FOR_TARGET` from `CFLAGS`, which the
gcc recipes set to `-O2 -g -pipe` only (see "Build flags"), so the
hardening flags do not reach the target libraries; those are built by the
new xgcc with the patched defaults.

The run-time libraries are the gcc-runtime output of the gcc build:
libgcc_s, libstdc++, libatomic (the compiler links it by default and
libstdc++ depends on it) and libgomp. C and C++ programs need them at run
time, so gcc-runtime is in `stages/core-libs` and a base system has them
without the compiler. The split follows Fedora's libgcc, libstdc++,
libatomic and libgomp packages: gcc-runtime holds the `lib*.so.N` files
programs load, and the libstdc++ gdb pretty-printers. Everything used only
when compiling or linking stays in gcc: the C++ headers, the compiler's own
directory `lib/gcc/<target>/<version>` (crt files, `libgcc.a`, `unwind.h`,
`omp.h`), the static libraries (Fedora's `-static` packages), the
unversioned `lib*.so` names the linker looks up, `libgomp.spec` and
`libstdc++.modules.json`. The `.la` files are deleted, as Fedora does.

gcc-bootstrap cannot work that way. It is linked by Fedora's g++ and needs
a libstdc++ in `/pos` while it is built, before it could produce one.
`gcc-runtime-bootstrap` builds the libraries alone first, as the LFS
"Libstdc++ from GCC" step does (plus libgcc and libatomic).
The compiler searches `/pos/include` as its system header directory, so gcc
requires linux-headers even though they are not part of the core-libs
archive.

The sdk archive ships gcc, the second build. A third, gcc built by itself,
should produce the same compiler and is not done; comparing the two would
be the check gcc's own `make bootstrap` does. gmp is `--enable-fat` because
the archive is installed on other machines.


# System stage
`stages/system` is init, the service manager, the login and account tools,
and the shell userland. It builds on core-libs.

* Left out for now: man-db with its groff, gdbm and libpipeline
  dependencies (a page viewer that costs four packages; each package still
  installs its man pages under `/pos/share/man`). Their recipes remain in
  `packages/` for reuse.
* file and which are user utilities in the base. GNU which is the GNU
  project's git tree on Savannah, with its build system in the cwm4
  submodule; `packages/which/prepare.sh` notes what its bootstrap needs.
* procps has the programs of Fedora's procps-ng: ps, top, free, pgrep,
  hugetop, pkill, pidof, pidwait, pmap, pwdx, skill, snice, slabtop, sysctl,
  tload, uptime, vmstat, w and watch, and libproc2. `w` reads sessions from
  logind. Its translated man pages are made by po4a (a host requirement),
  which leaves out those less than 80% translated.

## Overlapping binaries
Several programs are shipped by more than one project. Fedora and LFS pick
differently; POS follows Fedora except where noted.

| program | providers | POS |
| --- | --- | --- |
| login, su, nologin, sulogin, runuser | util-linux, shadow | util-linux; shadow `--without-su`, login/nologin deleted |
| chfn, chsh | util-linux, shadow | util-linux; shadow's deleted |
| vipw, vigr, newgrp | util-linux, shadow | shadow (sg has no other provider); util-linux `--disable-vipw --disable-newgrp` |
| groups | coreutils, shadow | coreutils; shadow's deleted |
| kill | util-linux, coreutils, procps, bash builtin | util-linux; coreutils `--enable-no-install-program=kill`; procps `--disable-kill` |
| uptime | coreutils, procps | procps; coreutils leaves it out |
| pidof | procps, sysvinit | procps (Fedora) |
| hostname | coreutils (off by default), systemd hostnamectl | coreutils `--enable-install-program=hostname` |
| lastlog | shadow (deprecated), util-linux lastlog2 | util-linux lastlog2 with pam_lastlog2; shadow default off |
| sh | bash, dash | bash (Fedora, Arch). One shell in the base; dash is an option later |
| awk | gawk, mawk | gawk (Fedora, Arch), including `-M` via core-libs gmp and mpfr |
| pager | less, more (util-linux) | both; less is what man and systemd call |
| bus daemon | dbus-daemon, dbus-broker | reference dbus-daemon for now. Fedora and Arch run dbus-broker; revisit when the base boots |
| privilege | sudo, systemd run0, su | sudo shipped as planned; run0 comes with systemd anyway |
| scheduled jobs | cronie, systemd timers | both. cronie needs a `run-parts` for cron.hourly, which no listed package provides (Fedora: crontabs, Debian: debianutils) |
| log rotation | logrotate, journald | journald handles the journal; logrotate for other files |
| man | man-db + groff + gdbm, mandoc | neither in the base (Scope). If a viewer is ever added, mandoc is one package where man-db is four |
| passwd.5, getspnam.3, crypt.3 | man-pages, shadow, libxcrypt | man-pages (sdk) for the first two, shadow's deleted; libxcrypt for crypt, man-pages' deleted |

## Deferred
* polkit: needs glib and duktape. glib is fine to add, but duktape's git tree
  generates its sources with a Python 2 `dist.py`; only release tarballs are
  buildable. systemd only dlopens polkit at run time, so nothing else in the
  stage waits on it.
* gettext tools: the base ships gettext-runtime only (gettext, ngettext,
  envsubst; libintl is glibc's). msgfmt, xgettext and autopoint are build
  tools for the sdk stage.

## Circular dependencies
systemd links libmount and libblkid from util-linux, and util-linux links
libsystemd (journal output for logger/lslogins). util-linux-bootstrap,
`--without-systemd`, is what systemd is built against; util-linux is built
after systemd `--with-systemd`. shadow and dbus require systemd so their
logind and sd_notify integration is on.

## Still missing for a bootable system
Upstream cronie and logrotate install no systemd units and no default
`logrotate.conf`; `run-parts` has no provider. These belong in a POS-owned
integration package (units, tmpfiles.d lines pointing at the factory tree,
sysusers.d), which does not exist yet. The root layout (symlinks above,
`/etc` seeding from the factory tree) is the other missing piece.
