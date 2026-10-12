#!/usr/bin/env bash
# Try out the RPM packages of a build (BUILD.md "RPM packages"), made by
# ./build rpm. Runs on the host or in a toolbox; dnf runs in a throwaway
# toolbox pos-<id>-try, which ./build clean also removes.
#
#   try-rpm.sh [-b <id>] pos              install pos and pos-sdk into the
#                                         toolbox: /pos next to Fedora, which
#                                         is unchanged
#   try-rpm.sh [-b <id>] root [<pkg>...]  make a root with pos-fedora and
#                                         the given Fedora packages
#   try-rpm.sh [-b <id>] dnf <args>...    run dnf on the root; pos-* names
#                                         are the build's RPM files
#   try-rpm.sh [-b <id>] run [<cmd>...]   run a command in the root (default:
#                                         a shell), with podman; changes are
#                                         discarded on exit
#   try-rpm.sh [-b <id>] clean            remove the root and the toolbox
#
# The default build is the current one. The root is work/builds/<id>/rpm-root.
#
# Examples:
#   ./build rpm
#   devtools/try-rpm.sh root vim-minimal procps-ng curl
#   devtools/try-rpm.sh dnf repoquery --installed      what got installed
#   devtools/try-rpm.sh run                            a shell in the root
#   devtools/try-rpm.sh run ldd /usr/bin/curl          Fedora curl on POS glibc
#   devtools/try-rpm.sh dnf -q repoquery --installed --whatprovides 'libc.so.6()(64bit)'
#   devtools/try-rpm.sh dnf install htop               add more on top
#   devtools/try-rpm.sh dnf install pos-debuginfo      the build's own work too
#   devtools/try-rpm.sh clean

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
builds=${base}/work/builds
# shellcheck source=../buildsys/config.sh
source "$base/buildsys/config.sh"
fedora_release=$(config fedora-release)

usage() {
  sed -n '/^#   try-rpm.sh/,/^#$/s/^# \{0,1\}//p' "$0" >&2
  exit 1
}

id=
if [[ ${1:-} == -b ]]; then
  id=${2:?}
  shift 2
fi
id=${id:-$(basename "$(readlink "${builds}/current")")}
bdir=${builds}/${id}
repo=${bdir}/rpm
root=${bdir}/rpm-root
tb=pos-${id}-try

# Paths as a toolbox sees them (the host root is under /run/host), and as
# the host sees them, wherever this runs.
in_toolbox() {
  [[ -f /run/.toolboxenv ]]
}
tb_path() {
  local home
  home=$(cd "$HOME" && pwd -P)
  if in_toolbox || [[ $1 == "$home" || $1 == "$home"/* ]]; then
    echo "$1"
  else
    echo "/run/host$1"
  fi
}
host_path() {
  if in_toolbox && [[ $1 == /run/host/* ]]; then
    echo "${1#/run/host}"
  else
    echo "$1"
  fi
}
host() {
  if in_toolbox; then
    flatpak-spawn --host "$@"
  else
    "$@"
  fi
}

tb_run() {
  if ! toolbox list -c | awk 'NR > 1 {print $2}' | grep -qx "$tb"; then
    toolbox create -y -r "$fedora_release" -c "$tb"
  fi
  (cd "$HOME" && toolbox run -c "$tb" "$@")
}

# dnf, with the build's RPM packages named as files: pos, pos-sdk,
# pos-fedora and pos-debuginfo are taken from the build, other names from
# Fedora.
dnf_pos() {
  local -a args=()
  local a
  for a in "$@"; do
    if [[ $a == pos || $a == pos-* ]] && [[ -f $repo/$a-$id-1.x86_64.rpm ]]; then
      a=$(tb_path "$repo/$a-$id-1.x86_64.rpm")
    fi
    args+=("$a")
  done
  tb_run sudo dnf "${args[@]}"
}

need_repo() {
  [[ -f $repo/pos-$id-1.x86_64.rpm ]] || {
    echo "no RPM packages in $bdir; run ./build rpm" >&2
    exit 1
  }
}
need_root() {
  [[ -d $root/usr ]] || {
    echo "no root in $root; run $0 root" >&2
    exit 1
  }
}

cmd=${1:-}
(($#)) && shift
case $cmd in
  pos)
    need_repo
    dnf_pos -y install pos pos-sdk
    tb_run rpm -q --whatprovides 'libc.so.6()(64bit)'
    tb_run /pos/bin/bash -c 'echo "POS bash $BASH_VERSION in /pos; /usr is Fedora"'
    ;;
  root)
    need_repo
    tb_run sudo rm -rf "$(tb_path "$root")"
    dnf_pos -y --installroot="$(tb_path "$root")" --releasever="$fedora_release" \
      --use-host-config --setopt=install_weak_deps=False install pos pos-sdk pos-fedora "$@"
    ;;
  dnf)
    need_repo
    need_root
    dnf_pos --installroot="$(tb_path "$root")" --releasever="$fedora_release" \
      --use-host-config --setopt=install_weak_deps=False "$@"
    ;;
  run)
    need_root
    (($#)) || set -- /usr/bin/bash -l
    # The root's files belong to the toolbox's root user, which rootless
    # podman maps the same way. :O mounts the root as an overlay.
    tty=()
    [[ -t 0 && -t 1 ]] && tty=(-it)
    host podman run --rm "${tty[@]}" --network=host \
      --env PATH=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin \
      --rootfs "$(host_path "$root"):O" "$@"
    ;;
  clean)
    if toolbox list -c | awk 'NR > 1 {print $2}' | grep -qx "$tb"; then
      [[ -d $root ]] && tb_run sudo rm -rf "$(tb_path "$root")"
      toolbox rm -f "$tb"
    elif [[ -d $root ]]; then
      echo "toolbox $tb is gone; remove $root as its owner (podman unshare rm -rf)" >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac
