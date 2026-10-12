#!/usr/bin/env bash
# Compare the packages of two builds: the files each package installs, and
# the libraries every ELF file in it links against (NEEDED). Differences
# between builds of the same sources point at what the build environment
# leaked into a package: a library found because it happened to be there,
# or a tool that changed the output.
#
#   compare-builds.sh <build> <build> [<package>...]
#
# A build is an ID in work/builds or work/references, or a directory with
# a dest/ of package trees. The default is every package of either build.
# Prints the differences; exits 1 when there are any.

set -euo pipefail
export LC_ALL=C

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

usage() {
  sed -n '/^#   compare-builds.sh/,/^#$/s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

build_dir() {
  local d
  for d in "$1" "$base/work/builds/$1" "$base/work/references/$1"; do
    if [[ -d $d/dest ]]; then
      echo "$d"
      return
    fi
  done
  echo "not a build: $1" >&2
  exit 2
}

(($# >= 2)) || usage
a=$(build_dir "$1")
b=$(build_dir "$2")
shift 2

# A package is built when its metadata is there (pkg_record writes it last).
built() {
  local f
  for f in "$1"/dest/*/pos/lib/pos/packages/*/meta; do
    [[ -f $f ]] && basename "$(dirname "$f")"
  done
  return 0
}

files() {
  cat "$1/dest/$2/pos/lib/pos/packages/$2/files"
}

needed() {
  local dest=$1/dest/$2 f
  while IFS= read -r -d '' f; do
    [[ $(head -c 4 "$f" | od -An -c | tr -d ' ') == 177ELF ]] || continue
    printf '%s: %s\n' "${f#"$dest"}" \
      "$(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | xargs)"
  done < <(find "$dest" -type f -print0) | sort
}

packages=("$@")
if ((${#packages[@]} == 0)); then
  mapfile -t packages < <({ built "$a"; built "$b"; } | sort -u)
fi

differ=0
for p in "${packages[@]}"; do
  if [[ ! -f $a/dest/$p/pos/lib/pos/packages/$p/meta ]]; then
    echo "== $p: only in $b"
    differ=1
    continue
  fi
  if [[ ! -f $b/dest/$p/pos/lib/pos/packages/$p/meta ]]; then
    echo "== $p: only in $a"
    differ=1
    continue
  fi
  out=$(diff <(files "$a" "$p") <(files "$b" "$p") | grep '^[<>]' || true)
  if [[ -n $out ]]; then
    echo "== $p: files"
    echo "$out"
    differ=1
  fi
  out=$(diff <(needed "$a" "$p") <(needed "$b" "$p") | grep '^[<>]' || true)
  if [[ -n $out ]]; then
    echo "== $p: NEEDED"
    echo "$out"
    differ=1
  fi
done
((differ == 0)) && echo "no differences in ${#packages[@]} packages"
exit $differ
