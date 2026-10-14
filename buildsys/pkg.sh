#!/usr/bin/env bash
# Helpers sourced by packages/*/build.sh.
#
# Recipes are run by buildsys/build.sh in a build container. The builder
# resolves the package's requirements, composes exactly that set as the
# container's /pos (read-only), and passes the result in the environment.
# Of the checkout, the container has the recipes (buildsys, packages), the
# package's source tree, and the build's build, dest and debug directories.
#
#   POS_BASE        the POS checkout
#   POS_PACKAGE     the package being built
#   POS_SRC_DIR     its source tree (src/<source>)
#   POS_WITH_SRC_DIRS  further source trees (meta "with-sources"), as
#                   <source>=<dir> words; pkg_sync_src copies each into
#                   the build tree
#   POS_BUILD_DIR   scratch build directory
#   POS_DEST_DIR    staging directory; the package installs into $POS_DEST_DIR/pos
#   POS_OUTPUTS     further packages this build produces (meta "outputs");
#                   the recipe installs each into $(pkg_output <name>)
#   POS_DEBUG_DIR   where pkg_finish puts the package's separate debug
#                   info, $POS_DEBUG_DIR/pos/lib/debug; an output's goes
#                   next to it, as with the staging directories
#   POS_ENV_SCRIPTS packages in the resolved environment that set up the
#                   build: pkg_setup sources packages/<name>/env.sh of each.
#                   The compiler comes from the package providing gcc (the
#                   reference's gcc, or gcc-host, Fedora's, without a
#                   reference); linking against /pos from the pos-link
#                   profile.

package=${POS_PACKAGE:?run recipes through buildsys/build.sh}

# A bootstrap package can source the main recipe after setting these. They
# are appended to the main recipe's configure arguments, where a later flag
# wins over an earlier one.
if ! declare -p configure_extra &>/dev/null; then
  configure_extra=()
fi

# Recipes run in a build container (buildsys/build.sh: build_container),
# not on the host or in a toolbox.
require_container() {
  if [[ ! -f /run/.containerenv || -f /run/.toolboxenv ]]; then
    echo "build scripts must run in a build container (./build)" >&2
    exit 1
  fi
}

pkg_setup() {
  base=${POS_BASE:?}
  src_dir=${POS_SRC_DIR:?}
  build_dir=${POS_BUILD_DIR:?}
  dest_dir=${POS_DEST_DIR:?}
  prefix=/pos
  # Configuration is read from the machine's /etc, never from inside the
  # prefix. Variable data is /var. Files a package installs under either
  # are shipped defaults; pkg_finish moves them to /pos/share/factory
  # (the systemd-tmpfiles factory tree).
  sysconfdir=/etc
  localstatedir=/var
  nproc=$(nproc)

  if [[ ! -d $src_dir ]]; then
    echo "missing sources: $src_dir" >&2
    exit 1
  fi

  debug_dir=${POS_DEBUG_DIR:?}
  rm -rf "$build_dir" "$dest_dir" "$debug_dir"
  mkdir -p "$build_dir" "$dest_dir"
  local o
  for o in ${POS_OUTPUTS:-}; do
    rm -rf "$(pkg_output "$o")" "$(dirname "$debug_dir")/${o:?}"
    mkdir -p "$(pkg_output "$o")"
  done

  pkg_flags

  local p
  for p in ${POS_ENV_SCRIPTS:-}; do
    # shellcheck source=/dev/null
    source "$base/packages/$p/env.sh"
  done
}

# Compiler and linker flags every package is built with (BUILD.md "Build
# flags"): optimized with debug info, which pkg_finish splits off, and the
# hardening Fedora and Arch build with. -fPIE and -fstack-protector-strong
# are the POS compiler's defaults (packages/gcc/build.sh). env.sh files add
# to these; recipes whose own build sets flags (glibc, gcc) replace them
# with pos_optflags.
pos_optflags="-O2 -g -pipe"
pkg_flags() {
  local harden="-fexceptions -Wp,-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fcf-protection"
  harden+=" -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
  export CFLAGS="$pos_optflags $harden"
  export CXXFLAGS="$pos_optflags $harden -Wp,-D_GLIBCXX_ASSERTIONS"
  export LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,--build-id=sha1"
}

# Staging directory of an output of this build.
pkg_output() {
  if [[ " ${POS_OUTPUTS:-} " != *" $1 "* ]]; then
    echo "${package}: $1 is not an output of this package" >&2
    exit 1
  fi
  echo "$(dirname "$dest_dir")/$1"
}

# Copy the source into the build tree, and each further source into a
# directory of it named after the source.
pkg_sync_src() {
  local w
  rsync -a --delete "$src_dir/" "$build_dir/"
  for w in ${POS_WITH_SRC_DIRS:-}; do
    rsync -a --delete "${w#*=}/" "$build_dir/${w%%=*}/"
  done
}


# Mark programs that must run set-uid root. The staging tree is written by an
# unprivileged user, so ownership is applied when the archive is extracted as
# root (assemble.sh records owner 0:0); only the mode bit is set here.
pkg_setuid() {
  local f
  for f in "$@"; do
    if [[ ! -f ${dest_dir}${f} ]]; then
      echo "${package}: setuid target missing: ${f}" >&2
      exit 1
    fi
    chmod 4755 "${dest_dir}${f}"
  done
}

pkg_cleanup() {
  rm -rf "$build_dir"
}

# Move shipped /etc and /var files into the factory tree. Reject anything a
# package tried to put in ${prefix}/etc or ${prefix}/var. A tmpfiles.d file
# of the package (factory-<package>.conf) copies each into place where it
# is missing (C lines), at boot and when an image is made.
pkg_factory() {
  local dest=${1:-$dest_dir} kind f
  local factory=${dest}${prefix}/share/factory
  local conf=${dest}${prefix}/lib/tmpfiles.d/factory-$(basename "$dest").conf
  rm -f "$conf"
  for kind in etc var; do
    if [[ -d ${dest}${prefix}/${kind} ]]; then
      echo "${package}: installed into ${prefix}/${kind}; use ${kind} outside the prefix" >&2
      exit 1
    fi
    if [[ -d ${dest}/${kind} ]]; then
      mkdir -p "$factory"
      rm -rf "${factory:?}/${kind}"
      mv "${dest}/${kind}" "${factory}/${kind}"
    fi
  done
  [[ -d $factory ]] || return 0
  mkdir -p "$(dirname "$conf")"
  # Files and links are copied; an empty directory (sudoers.d) is made
  # with its mode, as the factory tree loses it with the empty ones. Group
  # write is dropped unless sticky, as packaging does (rpm.sh, image.sh).
  (cd "$factory" && find . \( -type f -o -type l \) -printf '%P\n' | sort) |
    while read -r f; do
      echo "C /$f - - - - ${prefix}/share/factory/$f"
    done >"$conf"
  (cd "$factory" && find . -mindepth 1 -type d -empty -printf '%m %P\n' | sort -k2) |
    while read -r m f; do
      ((8#$m & 01000)) || m=$(printf '%o' $((8#$m & ~020)))
      echo "d /$f $m - - -"
    done >>"$conf"
  [[ -s $conf ]] || rm -f "$conf"
}

# A file belongs to one package: what an output holds is removed from the
# main package, so a recipe can install everything and then install the
# output's part again into the output.
pkg_split() {
  local o out f
  for o in ${POS_OUTPUTS:-}; do
    out=$(pkg_output "$o")
    pkg_factory "$out"
    (cd "$out" && find . ! -type d -print0) |
      while IFS= read -r -d '' f; do
        rm -f "${dest_dir}/${f#./}"
      done
  done
  find "$dest_dir" -mindepth 1 -depth -type d -empty -delete
}

# Split the debug info off the ELF programs and libraries of a staging
# tree and strip them, as Fedora's debuginfo packages do. The debug info
# goes to <debug>/pos/lib/debug/.build-id/<xx>/<rest>.debug, where gdb and
# debuginfod look it up by build ID. The loader keeps its symbol table
# (valgrind needs it) and static libraries lose only their debug info.
# Object files (crt*.o) are left as they are.
pkg_strip() {
  local dest=$1 debug=$2 f magic type id dbg mode
  local -A seen=()
  while IFS= read -r -d '' f; do
    # ELF, or an ar archive. A .a can also be a linker script (glibc's
    # libm.a), which is text.
    magic=$(head -c 8 "$f" | od -An -c | tr -d ' \n')
    [[ $magic == 177ELF* || $magic == '!<arch>\n' ]] || continue
    id=$(stat -c %d:%i "$f")
    [[ -z ${seen[$id]:-} ]] || continue
    seen[$id]=1
    mode=$(stat -c %a "$f")
    chmod u+w "$f"
    if [[ $magic == '!<arch>\n' ]]; then
      strip -g "$f"
    else
      type=$(readelf -h "$f" 2>/dev/null | awk '$1 == "Type:" {print $2}')
      if [[ $type == EXEC || $type == DYN ]]; then
        id=$(readelf -n "$f" 2>/dev/null | awk '$1 == "Build" && $2 == "ID:" {print $3}')
        if [[ -n $id ]]; then
          dbg=$debug/pos/lib/debug/.build-id/${id:0:2}/${id:2}.debug
          if [[ ! -e $dbg ]]; then
            mkdir -p "$(dirname "$dbg")"
            objcopy --only-keep-debug "$f" "$dbg"
            chmod 0644 "$dbg"
          fi
        else
          echo "${package}: no build ID, debug info dropped: ${f#"$dest"}" >&2
        fi
        case $f in
          */ld-linux-*.so.*) strip -g "$f" ;;
          *.so | *.so.*) strip --strip-unneeded "$f" ;;
          *) strip --strip-all "$f" ;;
        esac
      fi
    fi
    chmod "$mode" "$f"
  done < <(find "$dest" -type f -print0)
}

pkg_finish() {
  local o
  pkg_factory
  pkg_split
  pkg_strip "$dest_dir" "$debug_dir"
  for o in ${POS_OUTPUTS:-}; do
    pkg_strip "$(pkg_output "$o")" "$(dirname "$debug_dir")/$o"
  done
  pkg_cleanup
}
