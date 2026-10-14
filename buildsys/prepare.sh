#!/usr/bin/env bash
# Helpers sourced by packages/*/prepare.sh.
#
# Prepare turns a committed source tree into what a release tarball holds:
# translations and other files upstream's release process fetches, generated
# build system files, and a version. buildsys/build.sh runs it in a
# container of the build's tools image, with network access, once per source
# and inputs; builds then use the prepared tree and need no network. The
# container has the recipes, the committed source, src/gnulib and the tree
# to prepare; not the rest of the checkout. The environment:
#
#   POS_BASE        the POS checkout
#   POS_SOURCE      the source name (src/<source>)
#   POS_PREP_DIR    the tree to prepare, a copy of the committed src/<source>
#   POS_UPSTREAM    the committed src/<source>.upstream (ref, commit, date, url)
#   POS_WITH_SRC_DIRS  the package's further source trees (meta
#                   "with-sources"), as <source>=<dir> words; prep_setup
#                   copies each into the tree, as a directory named after it

source=${POS_SOURCE:?run prepare recipes through buildsys/build.sh}

require_container() {
  if [[ ! -f /run/.containerenv || -f /run/.toolboxenv ]]; then
    echo "prepare scripts must run in a build container (./build)" >&2
    exit 1
  fi
}

prep_setup() {
  base=${POS_BASE:?}
  prep_dir=${POS_PREP_DIR:?}
  cd "$prep_dir" || exit 1
  local w
  for w in ${POS_WITH_SRC_DIRS:-}; do
    rsync -a --delete "${w#*=}/" "$prep_dir/${w%%=*}/"
  done
  if [[ -x $base/src/gnulib/gnulib-tool ]]; then
    GNULIB_SRCDIR=$base/src/gnulib
    export GNULIB_SRCDIR
  fi
}

prep_upstream() {
  awk -v k="$1" '$1 == k {print $2}' "${POS_UPSTREAM:?}"
}

# A snapshot version for git-version-gen, which reads .tarball-version
# before asking git: <ref>-<upstream commit date>-<commit>, for example
# master-20260927-4b3b66d3328e. It names the upstream state and does not
# claim to be a release.
prep_version() {
  local ref commit date
  ref=$(prep_upstream ref)
  commit=$(prep_upstream commit)
  date=$(prep_upstream date)
  if [[ -z $ref || -z $commit || -z $date ]]; then
    echo "${source}: ref, commit or date missing in src/${source}.upstream" >&2
    exit 1
  fi
  version="${ref}-${date:0:4}${date:5:2}${date:8:2}-${commit:0:12}"
  printf '%s\n' "$version" > .tarball-version
}

# What upstream's bootstrap fetches before generating: translations,
# submodules and package hooks. gnulib comes from src/gnulib. The copy is
# not a git repository; an empty one stands in for hooks that run git
# submodule (tar's), and prep_finish removes it.
prep_pull() {
  git init -q
  if [[ -x ./autopull.sh ]]; then
    ./autopull.sh
  elif [[ -x ./bootstrap ]]; then
    ./bootstrap --pull --no-git
  fi
}

# Generate configure and the other build system files. Files taken from
# gnulib are copied, not linked to src/gnulib (see prep_finish).
prep_gen() {
  if [[ -x ./autogen.sh ]]; then
    ./autogen.sh
  elif [[ -x ./bootstrap ]]; then
    ./bootstrap --gen --copy
  elif [[ -f ./configure.ac || -f ./configure.in ]]; then
    autoreconf -fi
  fi
}

# The prepared tree has to stand alone, as a release tarball does. Some
# packages have gnulib-tool link imported files to src/gnulib whatever
# bootstrap is told (coreutils: --symlink in bootstrap.conf); those links
# are replaced by copies of their targets. gnulib-tool keeps a file it
# replaces as <file>~ (the m4 files autopoint copied before it); backups
# not in src/<source> are removed.
prep_finish() {
  local link target backup
  rm -rf .git autom4te.cache
  while IFS= read -r -d '' backup; do
    [[ -e $base/src/$source/$backup ]] || rm -f "$backup"
  done < <(find . -name '*~' ! -type d -print0)
  while IFS= read -r -d '' link; do
    target=$(readlink -f "$link")
    if [[ ! -f $target ]]; then
      echo "${source}: ${link} links outside the tree to ${target}" >&2
      exit 1
    fi
    cp --remove-destination -p "$target" "$link"
  done < <(find . -type l -lname '/*' -print0)
}
