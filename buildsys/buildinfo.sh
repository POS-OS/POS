#!/usr/bin/env bash
# What names a build's artifacts, from its info (work/builds/<id>/info).
# Sourced by the scripts that make or use them, with the build directory.
# BUILD.md "Build numbers".

# The value of a key in the info of the build in directory $1.
info_get() {
  awk -v k="$2" '$1 == k {print $2}' "$1/info"
}

# The part of artifact names that names the build: <version>-<id>, where
# the version is BUILD, or <BUILD>u<UPDATE> on a release line. The ID
# alone for a build made without VERSION.
build_stem() {
  local v
  v=$(info_get "$1" version)
  echo "${v:+$v-}$(basename "$1")"
}

# The version-release of the build's RPM packages: BUILD as the version,
# <UPDATE>.<id> as the release, UPDATE 0 on main, so an update sorts after
# the snapshot it was cut from. <id>-1 for a build made without VERSION.
rpm_evr() {
  local n u
  n=$(info_get "$1" build-number)
  u=$(info_get "$1" update)
  if [[ -n $n ]]; then
    echo "$n-${u:-0}.$(basename "$1")"
  else
    echo "$(basename "$1")-1"
  fi
}
