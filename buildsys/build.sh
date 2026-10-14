#!/usr/bin/env bash
# Build POS. Resolves package dependencies, runs each package build in a
# container of its own and assembles the stage archives. Runs on the host
# or in any toolbox; it needs podman.
#
# Every run belongs to a build, identified by a timestamp ID. A build keeps
# its outputs in work/builds/<id>. A package is built once per build; run
# continues the current build.
#
# A source with a prepare recipe (packages/<source>/prepare.sh) is prepared
# before it is built: the committed src/<source> is copied and turned into
# what a release tarball holds (buildsys/prepare.sh). Prepared trees are kept
# in work/sources/<source>/<key>, keyed by their inputs, and shared by
# builds.
#
# Every step of a build (prepare, package build, rpm, dnf image) runs in a
# container of the build's tools image: Fedora's container image with the
# Fedora packages every step declares, made when the build is created. A
# step sees that image and the paths it is given, nothing else of the host.
# A package build gets a /pos of exactly its resolved environment, composed
# for it and mounted read-only.
#
# A build is a toolchain build or a pos build (resolve.sh). The toolchain
# (gcc, binutils, the kernel headers) is built by toolchain builds, with
# the toolchain of a reference build, a stored toolchain build
# (work/references/<ref>, restored from the reference store), or Fedora's
# without one. A pos build builds the rest with its reference's toolchain,
# and assembles the stages with the reference's toolchain packages in
# them. podman runs on the host; from inside a toolbox through
# flatpak-spawn.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=resolve.sh
source "$base/buildsys/resolve.sh"
# shellcheck source=config.sh
source "$base/buildsys/config.sh"
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"

builds=$base/work/builds
CHECKS=yes
# Who commits VERSION bumps, as the source syncs are committed.
bot_name=pos-bot bot_email=pos-bot@devzero.dk
sources=$base/work/sources
refs=$base/work/references
fedora_release=$(config fedora-release)
fedora_image=registry.fedoraproject.org/fedora
export LC_ALL=C

usage() {
  cat >&2 <<EOF
usage: ./build plan [--new [--toolchain]] [<target>...]
                                               print what run would build, in order
       ./build run [--new [--toolchain] [--source-archives]] [--no-checks] [<target>...]
                                               build the targets, then assemble stage
                                               archives and images
       ./build prepare [<target>...]           prepare the sources of the targets now
       ./build rebuild <package>...            drop packages from the current build
       ./build rpm [<stage>...]                make RPM packages of the current build
       ./build image [--no-checks] [<image>...]
                                               make images of the current build again
       ./build status                          show the current build
       ./build reference [<id>]                store a complete toolchain build as
                                               the default reference
       ./build clean [<id>]                    remove the tools image of a build
       ./build validate [--unchecked] [<id>]   check that a build is an OS build
       ./build tag [--unchecked]               number the current build: validate it,
                                               tag its commit main-<BUILD>, then bump
       ./build bump                            commit VERSION with the next BUILD

A target is a stage (stages/<stage>/packages) or a package. The default is
every stage. run continues the current build; --new starts another, a
toolchain build with --toolchain. A toolchain build builds the toolchain
packages (meta: pipeline toolchain) and what they need; a pos build
builds the rest, and takes the toolchain from its reference. An
image (images/<image>/layout) is made when run assembles all its stages;
one made with dnf (images/<image>/packages) when run assembles all
stages, after the RPM packages; one made with podman
(images/<image>/containerfile) after the image it is made from.
--source-archives makes the new build also write an archive of every
source it built from (pos-src-<source>-<key>.tar.zst) and of the build
recipes (pos-recipes-<stem>.tar.zst).

A new build takes the toolchain from a reference build, a toolchain build,
by default the one reference marked last. A toolchain build without one
(reference none) is built by Fedora's compiler; a pos build needs one.
Settings (build.conf.dist) are read from
$build_config; an environment variable overrides one:
  fedora-release  POS_FEDORA_RELEASE  the Fedora release (default 44)
  tools-image     POS_TOOLS_IMAGE     the image tools are installed on
                                      (default $fedora_image:<release>)
  reference-dir   POS_REFERENCE_DIR   the reference store
  reference       POS_REFERENCE       the reference build, or none
EOF
  exit 1
}

in_toolbox() {
  [[ -f /run/.toolboxenv ]]
}

# Paths as the host sees them, for podman.
host_path() {
  if in_toolbox && [[ $1 == /run/host/* ]]; then
    echo "${1#/run/host}"
  else
    echo "$1"
  fi
}

# podman of the host. From inside a toolbox it is reached the way the
# toolbox CLI reaches itself, through flatpak-spawn; podman nested in the
# toolbox container is not used.
host_podman() {
  if in_toolbox; then
    flatpak-spawn --host podman "$@"
  else
    podman "$@"
  fi
}

# The Fedora packages of the tools image: the host-requires and
# prepare-requires of every package, so any step of the run finds what it
# declares, rpm-build for the RPM packages (buildsys/rpm.sh), and
# systemd-repart, the tools it makes file systems with and qemu-img, for
# disks (buildsys/image-disk.sh).
tools_packages() {
  local p
  {
    for p in "${PKGS[@]}"; do
      echo ${HREQ[$p]} ${PREQ[$p]}
    done
    echo rpm-build systemd-standalone-repart dosfstools mtools e2fsprogs qemu-img
  } | xargs -n1 | sort -u
}

# Make the build's tools image, localhost/pos-tools:<id>, from the pinned
# base (info: tools-base), and record its packages in tools-packages.
tools_build() {
  local from=$1 log=$bdir/logs/tools.log
  tools_packages >"$bdir/tools-packages.tmp"
  echo "=== tools image localhost/pos-tools:$id from $from ===" | tee "$log" >&2
  host_podman build --build-arg "BASE=$from" \
    --build-arg "PACKAGES=$(xargs <"$bdir/tools-packages.tmp")" \
    --label "pos.build=$id" -t "localhost/pos-tools:$id" \
    -f "$(host_path "$base/buildsys/tools.containerfile")" "$(host_path "$base/buildsys")" 2>&1 |
    tee -a "$log" >&2
  mv "$bdir/tools-packages.tmp" "$bdir/tools-packages"
}

# The base of a new build's tools image, pulled now and pinned by digest,
# so the build keeps it when the tag moves on.
tools_base() {
  local from pinned
  from=$(config tools-image)
  from=${from:-$fedora_image:$fedora_release}
  [[ $from == localhost/* ]] || host_podman pull -q "$from" >/dev/null
  pinned=$(host_podman image inspect --format '{{index .RepoDigests 0}}' "$from" 2>/dev/null) || pinned=
  [[ -n $pinned && $pinned != "<no value>" ]] ||
    pinned=$(host_podman image inspect --format '{{.Id}}' "$from") || die "no image $from"
  echo "$pinned"
}

# The tools image has the host-requires of every package as they were when
# it was made. It is made again, on the same base, when a package now
# declares more, or when it was removed (clean).
tools_ensure() {
  local missing
  missing=$(tools_packages | comm -13 "$bdir/tools-packages" - | xargs)
  if [[ -n $missing ]]; then
    echo "tools image: adding $missing" >&2
  elif host_podman image exists "localhost/pos-tools:$id"; then
    return 0
  fi
  tools_build "$(build_info tools-base)"
}

# The reference a new build uses: the reference setting, else the one the
# reference store marks the default, else none.
reference_choose() {
  local ref store
  ref=$(config reference)
  store=$(config reference-dir)
  if [[ -z $ref && -n $store && -f $store/default ]]; then
    ref=$(<"$store/default")
  fi
  echo "${ref:-none}"
}

# Unpack a reference from the store into work/references/<ref>, unless it
# is there. The store is a directory; this is where a remote one would be
# fetched from.
reference_restore() {
  local ref=$1 store archive
  [[ $ref != none && ! -f $refs/$ref/info ]] || return 0
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference $ref is not in $refs, and reference-dir is not set"
  archive=$store/pos-ref-$ref.tar.zst
  [[ -f $archive ]] || die "no reference $ref: missing $archive"
  echo "restoring reference $ref from $archive" >&2
  rm -rf "$refs/$ref.tmp"
  mkdir -p "$refs/$ref.tmp"
  tar --zstd -xf "$archive" -C "$refs/$ref.tmp"
  mv "$refs/$ref.tmp" "$refs/$ref"
}

# The packages of a reference the resolver may use, with the requirements
# they were built with (resolve.sh: REF, REF_REQ). A reference is a
# toolchain build.
load_reference() {
  local ref=$1 meta p
  REF=() REF_REQ=()
  [[ $ref != none ]] || return 0
  [[ $(awk '$1 == "pipeline" {print $2}' "$refs/$ref/info") == toolchain ]] ||
    die "reference $ref is not a toolchain build; make one with: POS_REFERENCE=none ./build run --new --toolchain"
  for meta in "$refs/$ref"/dest/*/pos/lib/pos/packages/*/meta; do
    [[ -f $meta ]] || continue
    p=$(basename "$(dirname "$meta")")
    [[ -n ${KIND[$p]:-} ]] || continue
    REF[$p]=1
    REF_REQ[$p]=$(awk '$1 == "requires" {$1 = ""; print}' "$meta" | xargs)
  done
  return 0
}

# The reference of the build; none for builds from before references.
build_reference() {
  local ref
  ref=$(build_info reference)
  echo "${ref:-none}"
}

# The run's progress in the terminal title, for whoever watches it. It is
# written to the terminal, so it stays out of the output and the logs. Under
# tmux it is the pane title, which the default status line shows. The title
# from before the run is put back when it ends.
TITLE=
TITLE_SAVED=
declare -A STAGE_OF=()

title_init() {
  [[ -t 2 ]] && { : >/dev/tty; } 2>/dev/null || return 0
  TITLE=1
  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null; then
    TITLE_SAVED=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_title}' 2>/dev/null) || true
  else
    printf '\e[22;0t' >/dev/tty
  fi
  trap title_restore EXIT
}

title() {
  [[ -n $TITLE ]] || return 0
  printf '\e]2;pos %s\a' "$*" >/dev/tty 2>/dev/null || true
}

title_restore() {
  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null; then
    tmux select-pane -t "${TMUX_PANE:-}" -T "$TITLE_SAVED" 2>/dev/null || true
  else
    printf '\e[23;0t' >/dev/tty 2>/dev/null || true
  fi
}

# The target stages that list each build (a package, or the package an
# output is built by), for the title.
stages_of() {
  local s p b
  STAGE_OF=()
  for s in "$@"; do
    [[ -f $base/stages/$s/packages ]] || continue
    while read -r p; do
      p=${p%%#*}
      p=${p//[[:space:]]/}
      [[ -n $p ]] || continue
      b=$(build_of "$p")
      [[ ,${STAGE_OF[$b]:-}, == *,$s,* ]] || STAGE_OF[$b]+=${STAGE_OF[$b]:+,}$s
    done <"$base/stages/$s/packages"
  done
}

current_id() {
  [[ -L $builds/current ]] && basename "$(readlink "$builds/current")"
}

# Writes progress to stderr; the ID is the output.
build_new() {
  local archives=$1 ref from
  id=$(date +%Y%m%d%H%M)
  [[ ! -e $builds/$id ]] || die "build $id already exists; wait a minute"
  ref=$(reference_choose)
  [[ $ref != none || $PIPELINE == toolchain ]] ||
    die "a pos build takes the toolchain from a reference; make one with: POS_REFERENCE=none ./build run --new --toolchain"
  reference_restore "$ref"
  from=$(tools_base)
  bdir=$builds/$id
  mkdir -p "$bdir"/{dest,debug,build,logs}
  tools_build "$from"
  {
    echo "id $id"
    echo "pipeline $PIPELINE"
    echo "fedora $fedora_release"
    echo "tools-base $from"
    echo "tools-image localhost/pos-tools:$id"
    echo "reference $ref"
    echo "branch $(git -C "$base" rev-parse --abbrev-ref HEAD)"
    tree_state | awk '{print "commit", $1; print "tree", $2}'
    version_info HEAD
    echo "started $(date -u +%FT%TZ)"
    echo "source-archives $archives"
  } >"$builds/$id/info"
  ln -sfn "$id" "$builds/current"
  echo "$id"
}

build_info() {
  info_get "$bdir" "$1"
}

# The commit the checkout is at, and clean or dirty: tracked files that
# differ from it, or files not added yet where the build reads its
# instructions. Recorded for the build, each package and each step made,
# so validate can tell that a build was made from one commit.
tree_state() {
  local dirty
  dirty=$(git -C "$base" --no-optional-locks status --porcelain --untracked-files=no
          git -C "$base" --no-optional-locks status --porcelain -- VERSION buildsys packages stages images rpm devtools)
  if [[ -n $dirty ]]; then
    echo "$(git -C "$base" rev-parse HEAD) dirty"
  else
    echo "$(git -C "$base" rev-parse HEAD) clean"
  fi
}

# Each producer of a build records what it made, in made/<name>
# (package-<package>, stage-<stage>, rpm, image-<image>), with the checkout
# it made it from (tree_state), and "unchecked" when its checks were
# skipped. A producer drops its record, and complete, before it starts
# (step_start), so a failed one leaves none. A default run that finishes
# records complete. rebuild drops the dropped packages' records and
# everything made from packages. validate reads only these records.
step_start() {
  rm -f "$bdir/made/$1" "$bdir/made/complete"
}

step_made() {
  mkdir -p "$bdir/made"
  echo "$(tree_state)${2:+ $2}" >"$bdir/made/$1"
}

# Load the build in bdir: its pipeline (pos for builds from before
# pipelines), what it has built and its reference.
build_load() {
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  load_built
  reference_restore "$(build_reference)"
  load_reference "$(build_reference)"
}

# The committed state of a source: builds and archives must match a commit.
source_tree() {
  local s=$1
  if [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- "src/$s" "src/$s.upstream") ]]; then
    die "src/$s has uncommitted changes; commit them before building"
  fi
  git -C "$base" rev-parse "HEAD:src/$s"
}

has_prepare() {
  [[ -f $base/packages/$1/prepare.sh ]]
}

upstream_info() {
  git -C "$base" show "HEAD:src/$1.upstream" 2>/dev/null ||
    die "src/$1.upstream is not committed; prepare reads it from HEAD"
}

# The key of a prepared tree: everything that goes into it.
prepare_key() {
  local s=$1 w
  {
    source_tree "$s"
    upstream_info "$s"
    cat "$base/packages/$s/prepare.sh" "$base/buildsys/prepare.sh"
    echo "${PREQ[$s]}"
    if [[ -f $base/src/$s/bootstrap.conf || -x $base/src/$s/autopull.sh ]]; then
      source_tree gnulib
    fi
    for w in ${WSRC[$s]}; do
      source_tree "$w"
    done
  } | sha256sum | cut -c1-16
}

# Prepare a source unless a tree with the same key exists. Sets PREPARED to
# the prepared tree. Prepare has network: it fetches what upstream's
# release process does. It sees the committed source (prepare recipes
# compare with it), src/gnulib, and the committed sources of the package's
# with-sources, which upstream's bootstrap may take files from (tar's and
# cpio's paxutils).
prepare_source() {
  local s=$1 key dir log hbase w with_dirs=
  local -a mounts
  key=$(prepare_key "$s") || exit 1
  dir=$sources/$s/$key
  PREPARED=$dir
  [[ -f $dir.done ]] && return
  log=$bdir/logs/prepare-$s.log
  hbase=$(host_path "$base")
  rm -rf "$dir" "$dir.tmp"
  mkdir -p "$dir.tmp"
  git -C "$base" archive --format=tar "HEAD:src/$s" | tar -x -C "$dir.tmp"
  upstream_info "$s" >"$dir.upstream"
  mounts=(net ro:"$base/buildsys" ro:"$base/packages" ro:"$base/src/$s" rw:"$dir.tmp" ro:"$dir.upstream")
  [[ ! -d $base/src/gnulib ]] || mounts+=(ro:"$base/src/gnulib")
  for w in ${WSRC[$s]}; do
    mounts+=(ro:"$base/src/$w")
    with_dirs+=" $w=$hbase/src/$w"
  done
  title "prepare $s"
  echo "=== prepare $s ($key) ===" | tee "$log"
  step_run "prepare-$s" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_SOURCE="$s" \
    POS_PREP_DIR="$(host_path "$dir.tmp")" \
    POS_UPSTREAM="$(host_path "$dir.upstream")" \
    POS_WITH_SRC_DIRS="${with_dirs# }" \
    bash "$hbase/packages/$s/prepare.sh" 2>&1 | tee -a "$log"
  mv "$dir.tmp" "$dir"
  touch "$dir.done"
}

marker() {
  echo "$bdir/dest/$1/pos/lib/pos/packages/$1/meta"
}

load_built() {
  local p
  BUILT=()
  for p in "${PKGS[@]}"; do
    [[ -f $(marker "$p") ]] && BUILT[$p]=1
  done
  return 0
}

# Write the package metadata into its staging tree. It is installed with
# the package, so a /pos tree records what it contains. The meta file is
# written last: its presence marks the package built.
pkg_record() {
  local p=$1 dest=$bdir/dest/$1 dir extra s
  [[ -d $dest/pos ]] || die "$p: nothing installed into $dest/pos"
  extra=$(find "$dest" -mindepth 1 -maxdepth 1 ! -name pos -print)
  if [[ -n $extra ]]; then
    echo "warning: $p installed paths outside /pos:" >&2
    echo "$extra" >&2
  fi
  # /pos/lib is the only library directory (BUILD.md "Library directory").
  # lib64 comes from build tools that look at the tools image's
  # /usr/lib64 (meson, cmake GNUInstallDirs, Fedora's gcc).
  extra=$(find "$dest/pos" -mindepth 1 -maxdepth 1 \( -name lib64 -o -name lib32 -o -name libx32 \) -print)
  [[ -z $extra ]] || die "$p: installed into $(echo "$extra" | xargs -n1 basename | xargs); set libdir to /pos/lib"
  dir=$dest/pos/lib/pos/packages/$p
  mkdir -p "$dir"
  (cd "$dest" && find pos -mindepth 1 ! -type d ! -path "pos/lib/pos/packages/*" | sed 's|^|/|' | sort) >"$dir/files"
  {
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$base/packages/$p/meta"
    echo "build $id"
    echo "build-source ${SRC[$(build_of "$p")]} ${SOURCE_ID:-}"
    for s in "${WITH_SOURCE_IDS[@]}"; do
      echo "build-with-source $s"
    done
    echo "build-env ${ENV[*]}"
    echo "build-tools $TOOLS_ID"
    echo "build-reference $(build_reference)"
    echo "built $(date -u +%FT%TZ)"
  } >"$dir/meta.tmp"
  mv "$dir/meta.tmp" "$dir/meta"
  step_made "package-$p"
}

# The staging tree of a package in the environment: this build's, or the
# reference's (<name>@ref).
env_tree() {
  if is_ref "$1"; then
    echo "$refs/$(build_reference)/dest/${1%@ref}/pos"
  else
    echo "$bdir/dest/$1/pos"
  fi
}

# Compose the /pos of a package build: the trees of the POS packages in
# ENV hard-linked into one directory, which the build container mounts
# read-only. A path has one owner: cp fails on a path another package of
# the environment already put there.
root_compose() {
  local root=$1 q
  rm -rf "$root"
  mkdir -p "$root"
  for q in "${ENV[@]}"; do
    case ${KIND[${q%@ref}]} in
      package|output)
        cp -al --update=none-fail "$(env_tree "$q")/." "$root/" ||
          die "$p: ${q%@ref} ships a path another package of the environment ships" ;;
    esac
  done
}

# Run a step of the build in a container of its tools image. The step sees
# the image and what it is given: ro:<path> and rw:<path> mount a path at
# its host path, read-only or read-write, and pos:<path> mounts a composed
# root as /pos, read-only. The user is the caller and there is no network,
# unless given net (network) or root: the container's root, which is the
# caller outside it, allowed to mount in the container's own namespaces
# (SYS_ADMIN of rootless podman covers its user namespace only).
step_run() {
  local name=$1 a h net=--network=none user=--userns=keep-id
  local -a mounts=()
  shift
  while [[ $1 != -- ]]; do
    a=$1
    shift
    h=$(host_path "${a#*:}")
    case $a in
      net) net= ;;
      root) user=--cap-add=SYS_ADMIN ;;
      ro:*) mounts+=(-v "$h:$h:ro") ;;
      rw:*) mounts+=(-v "$h:$h") ;;
      pos:*) mounts+=(-v "$h:/pos:ro") ;;
      *) die "step_run: unknown argument $a" ;;
    esac
  done
  shift
  host_podman run --rm --replace --name "pos-$id-$name" ${net:+"$net"} ${user:+"$user"} \
    --security-opt label=disable --pids-limit=-1 --ulimit=host \
    "${mounts[@]}" -w /tmp -e HOME=/tmp -e LC_ALL=C \
    "$(build_info tools-image)" "$@"
}

# The tree a source is built from, and its identity for the package
# metadata and the source archives: the prepared tree's key, or the
# committed tree. Sets SOURCE_DIR and SOURCE_KEY.
source_of() {
  local s=$1
  SOURCE_DIR=$base/src/$s
  if has_prepare "$s"; then
    prepare_source "$s"
    SOURCE_DIR=$PREPARED
    SOURCE_KEY=$(basename "$PREPARED")
  elif [[ -d $base/src/$s ]]; then
    SOURCE_KEY=$(source_tree "$s")
  else
    SOURCE_KEY=
  fi
}

build_one() {
  local p=$1 q scripts log root
  env_of "$p" || die "$p: unresolved: ${MISSING[*]}"
  scripts=$(env_scripts | xargs)
  log=$bdir/logs/$p.log
  root=$bdir/roots/$p
  local hbase hbdir src_dir s with_dirs=
  hbase=$(host_path "$base")
  hbdir=$(host_path "$bdir")
  for q in "$p" ${OUTS[$p]}; do
    step_start "package-$q"
  done
  source_of "${SRC[$p]}"
  src_dir=$SOURCE_DIR
  SOURCE_ID=$SOURCE_KEY
  # The package's own inputs: the recipes (they source each other's),
  # its source trees, and the build's build, dest and debug directories.
  local -a mounts=(pos:"$root" ro:"$base/buildsys" ro:"$base/packages")
  [[ ! -d $src_dir ]] || mounts+=(ro:"$src_dir")
  WITH_SOURCE_IDS=()
  for s in ${WSRC[$p]}; do
    source_of "$s"
    mounts+=(ro:"$SOURCE_DIR")
    with_dirs+=" $s=$(host_path "$SOURCE_DIR")"
    WITH_SOURCE_IDS+=("$s $SOURCE_KEY")
  done
  mounts+=(rw:"$bdir/build" rw:"$bdir/dest" rw:"$bdir/debug")

  echo "=== $p: setup: ${scripts:-none} ===" | tee "$log"
  echo "env: ${ENV[*]}" | tee -a "$log"
  root_compose "$root"
  step_run "$p" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_PACKAGE="$p" \
    POS_SRC_DIR="$(host_path "$src_dir")" \
    POS_WITH_SRC_DIRS="${with_dirs# }" \
    POS_BUILD_DIR="$hbdir/build/$p" \
    POS_DEST_DIR="$hbdir/dest/$p" \
    POS_DEBUG_DIR="$hbdir/debug/$p" \
    POS_OUTPUTS="${OUTS[$p]# }" \
    POS_ENV_SCRIPTS="$scripts" \
    bash "$hbase/packages/$p/build.sh" 2>&1 | tee -a "$log"
  for q in "$p" ${OUTS[$p]}; do
    pkg_record "$q"
    BUILT[$q]=1
  done
  # Kept when the build fails, to look at.
  rm -rf "$root"
}

report_stuck() {
  local p
  echo "cannot build:" >&2
  for p in "${WANTED[@]}"; do
    env_of "$p" || echo "  $p: needs ${MISSING[*]}" >&2
  done
  exit 1
}

cmd_plan() {
  local id= bdir n=0 t toolchain=
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) id="<new>" ;;
      --toolchain) toolchain=1 ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  [[ -z $toolchain || -n $id ]] || die "--toolchain is chosen when a build is created; use it with --new"
  local ref
  if [[ -z $id ]] && id=$(current_id); then
    bdir=$builds/$id
    build_load
    ref=$(build_reference)
  else
    id="<new>"
    PIPELINE=${toolchain:+toolchain}
    PIPELINE=${PIPELINE:-pos}
    ref=$(reference_choose)
    [[ $ref != none || $PIPELINE == toolchain ]] || die "a pos build takes the toolchain from a reference"
    reference_restore "$ref"
    load_reference "$ref"
  fi
  ((${#args[@]})) || mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  [[ $PIPELINE == toolchain ]] || targets_check "${TARGETS[@]}"
  echo "build $id ($PIPELINE)"
  echo "reference $ref (${#REF[@]} packages)"
  while next_package "${TARGETS[@]}"; do
    env_of "$NEXT"
    printf '%3d %-24s setup: %s\n' $((++n)) "$NEXT" "$(env_scripts | xargs)"
    printf '    env: %s\n' "${ENV[*]}"
    for t in "$NEXT" ${OUTS[$NEXT]}; do
      BUILT[$t]=1
    done
  done
  wanted "${TARGETS[@]}"
  ((${#WANTED[@]} == 0)) || report_stuck
  ((n > 0)) || echo "nothing to build"
}

# Archive every source the build's packages were built from, as recorded in
# their metadata (build-source, build-with-source), and the build recipes.
source_archives() {
  local p s key out commit
  local -A seen=()
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package && -n ${BUILT[$p]:-} ]] || continue
    while read -r s key; do
      [[ -z ${seen[$s]:-} ]] || continue
      seen[$s]=1
      if [[ -z $key ]]; then
        echo "note: no source archive for $s: src/$s is not in the repository"
        continue
      fi
      out=$bdir/pos-src-$s-${key:0:16}.tar.zst
      [[ -f $out ]] && continue
      if [[ -d $sources/$s/$key ]]; then
        tar --zstd -cf "$out.tmp" -C "$sources/$s" --transform "s,^$key,$s," "$key"
      else
        git -C "$base" archive --format=tar --prefix="$s/" "$key" | zstd -q -o "$out.tmp"
      fi
      mv "$out.tmp" "$out"
      echo "$out"
    done < <(awk '$1 == "build-source" || $1 == "build-with-source" {print $2, $3}' "$(marker "$p")")
  done
  commit=$(git -C "$base" rev-parse HEAD)
  if [[ $commit != "$(build_info commit)" ]] ||
     [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- buildsys packages stages images rpm) ]]; then
    echo "warning: buildsys, packages, stages, images or rpm differ from the commit the build started at;" \
         "the recipes archive holds HEAD" >&2
  fi
  out=$bdir/pos-recipes-$(build_stem "$bdir").tar.zst
  git -C "$base" archive --format=tar --prefix="pos-recipes-$(build_stem "$bdir")/" HEAD \
    buildsys packages stages images rpm BUILD.md README.md | zstd -q -f -o "$out.tmp"
  mv "$out.tmp" "$out"
  echo "$out"
}

# The images (images/<image>/layout) whose stages are all among the given ones.
layout_images_of() {
  local layout s
  for layout in "$base"/images/*/layout; do
    [[ -f $layout ]] || continue
    for s in $(awk '$1 == "stage" {print $2}' "$layout"); do
      [[ " $* " == *" $s "* ]] || continue 2
    done
    basename "$(dirname "$layout")"
  done
}

# The images made with dnf (images/<image>/packages), when the given stages
# are all stages: they install the pos RPM package, which holds them all.
dnf_images_of() {
  local list s
  for s in $(all_stages); do
    [[ " $* " == *" $s "* ]] || return 0
  done
  for list in "$base"/images/*/packages; do
    [[ -f $list ]] && basename "$(dirname "$list")"
  done
  return 0
}

# The images made with podman (images/<image>/containerfile) from one of
# the given images (images/<image>/from).
podman_images_of() {
  local file
  for file in "$base"/images/*/containerfile; do
    [[ -f $file ]] || continue
    [[ " $* " == *" $(image_from "$(basename "$(dirname "$file")")") "* ]] &&
      basename "$(dirname "$file")"
  done
  return 0
}

image_from() {
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$base/images/$1/from" | xargs
}

# The name of an image in podman: images/container is pos,
# images/container-<x> and images/<x> are pos-<x>.
podman_name() {
  case $1 in
    container) echo pos ;;
    container-*) echo "pos-${1#container-}" ;;
    *) echo "pos-$1" ;;
  esac
}

# Import an image archive of the build into podman as <name>:<id>.
# images/container has POS's own layout; the others are Fedora layouts,
# where most of /pos/bin is linked into /usr/bin.
podman_import() {
  local t=$1 path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
  [[ $t != container ]] || path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin
  host_podman import --change "ENV PATH=$path" --change 'CMD ["/usr/bin/bash"]' \
    --change "LABEL pos.build=$id" --change "LABEL pos.version=$(info_get "$bdir" version)" \
    "$(host_path "$bdir/pos-image-$t-$(build_stem "$bdir").tar.zst")" "$(podman_name "$t"):$id"
}

# Make an image with podman from images/<image>/containerfile, on top of
# the build's image named in images/<image>/from (BASE). It is tagged
# with the build ID and with the Fedora release, the tag a new build
# looks for.
podman_image() {
  local t=$1 from name
  from=$(image_from "$t")
  [[ -f $bdir/pos-image-$from-$(build_stem "$bdir").tar.zst ]] || die "$t: build $id has no $from image; make it first"
  podman_import "$from"
  name=localhost/$(podman_name "$t")
  host_podman build --build-arg "BASE=localhost/$(podman_name "$from"):$id" \
    --label "pos.build=$id" --label "pos.version=$(info_get "$bdir" version)" -t "$name:$id" \
    -f "$(host_path "$base/images/$t/containerfile")" "$(host_path "$base/images/$t")"
  host_podman tag "$name:$id" "$name:$(build_info fedora)"
  echo "$name:$id"
}

# Make the RPM packages of the given stages (buildsys/rpm.sh). It needs
# network: pos-fedora takes the provides of the Fedora packages it stands
# in for from Fedora's repositories.
rpm_make() {
  step_start rpm
  step_run rpm net ro:"$base/buildsys" ro:"$base/stages" ro:"$base/rpm" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/rpm.sh")" "$(host_path "$bdir")" "$@"
  step_made rpm
}

# Make an image with dnf (buildsys/image-dnf.sh), as root: dnf installs
# files owned by the users packages create. It needs network for Fedora's
# repositories.
dnf_image() {
  step_run "image-$1" net root ro:"$base/buildsys" ro:"$base/images" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/image-dnf.sh")" "$(host_path "$bdir")" "$1"
}

# Install the Fedora kernel packages of images/<image>/kernel into a
# layout image (buildsys/image-kernel.sh), as root: kernel-install runs in
# the image's tree. It needs network for Fedora's repositories.
kernel_image() {
  step_run "kernel-$1" net root ro:"$base/buildsys" ro:"$base/images" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/image-kernel.sh")" "$(host_path "$bdir")" "$1"
}

disk_image() {
  step_run "disk-$1" root ro:"$base/buildsys" ro:"$base/images" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/image-disk.sh")" "$(host_path "$bdir")" "$1"
}

# Make the images of the given names: layout images from the stage
# archives, dnf images from the RPM packages, podman images from another
# image. A layout image with images/<image>/kernel gets that kernel. A
# layout or dnf image with images/<image>/repart.d also gets a disk.
make_images() {
  local t
  for t in "$@"; do
    title "image $t"
    step_start "image-$t"
    if [[ -f $base/images/$t/layout ]]; then
      "$base/buildsys/image.sh" "$bdir" "$t"
      [[ ! -f $base/images/$t/kernel ]] || kernel_image "$t"
    elif [[ -f $base/images/$t/packages ]]; then
      dnf_image "$t"
    else
      podman_image "$t"
      image_made "$t"
      continue
    fi
    if [[ -d $base/images/$t/repart.d ]]; then
      disk_image "$t"
    fi
    image_made "$t"
  done
}

# Run an image's check and record the image. images/<image>/check names a
# script that devtools/vm.sh runs in the image's booted disk
# (devtools/smoke.sh); with --no-checks (CHECKS no) it is skipped and the
# image recorded unchecked.
image_made() {
  local t=$1 script
  if [[ -f $base/images/$t/check ]]; then
    if [[ $CHECKS == no ]]; then
      step_made "image-$t" unchecked
      return 0
    fi
    script=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$base/images/$t/check")
    title "check $t"
    "$base/devtools/vm.sh" -i "$t" -c "$base/$script" "$id" ||
      die "image $t: its check $script failed (--no-checks skips it)"
  fi
  step_made "image-$t"
}

cmd_run() {
  local new= archives=no t toolchain= all=
  local -a args=() stages=()
  for t in "$@"; do
    case $t in
      --new) new=1 ;;
      --toolchain) toolchain=1 ;;
      --source-archives) archives=yes ;;
      --no-checks) CHECKS=no ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  if [[ $archives == yes && -z $new ]]; then
    die "--source-archives is chosen when a build is created; use it with --new"
  fi
  [[ -z $toolchain || -n $new ]] || die "--toolchain is chosen when a build is created; use it with --new"
  if [[ -n $new ]] || ! id=$(current_id); then
    PIPELINE=${toolchain:+toolchain}
    PIPELINE=${PIPELINE:-pos}
    id=$(build_new "$archives")
    echo "new build $id"
  fi
  bdir=$builds/$id
  [[ -n $(build_info tools-image) ]] ||
    die "build $id builds in toolboxes, which this buildsys no longer does; start another with run --new"
  build_load
  echo "build $id ($PIPELINE), reference $(build_reference) (${#REF[@]} packages)"
  if ((${#args[@]} == 0)); then
    all=1
    mapfile -t args < <(pipeline_targets)
  fi
  targets_expand "${args[@]}"
  [[ $PIPELINE == toolchain ]] || targets_check "${TARGETS[@]}"
  tools_ensure
  TOOLS_ID=$(host_podman image inspect --format '{{.Id}}' "$(build_info tools-image)")

  # The total is what is wanted now; it can shift a little as outputs and
  # obsoletes resolve.
  local n=0 total
  title_init
  stages_of "${args[@]}"
  wanted "${TARGETS[@]}"
  total=${#WANTED[@]}
  while next_package "${TARGETS[@]}"; do
    title "$((++n))/$total $NEXT${STAGE_OF[$NEXT]:+ [${STAGE_OF[$NEXT]}]}"
    build_one "$NEXT"
  done
  wanted "${TARGETS[@]}"
  ((${#WANTED[@]} == 0)) || report_stuck

  for t in "${args[@]}"; do
    [[ -f $base/stages/$t/packages ]] && stages+=("$t")
  done
  for t in "${stages[@]}"; do
    title "assemble $t"
    step_start "stage-$t"
    "$base/buildsys/assemble.sh" "$bdir" "$t" "$refs/$(build_reference)"
    step_made "stage-$t"
  done
  local -a layout_images dnf_images podman_images
  mapfile -t layout_images < <(layout_images_of "${stages[@]}")
  make_images "${layout_images[@]}"
  mapfile -t dnf_images < <(dnf_images_of "${stages[@]}")
  if ((${#dnf_images[@]})); then
    title "rpm"
    rpm_make "${stages[@]}"
    make_images "${dnf_images[@]}"
  fi
  mapfile -t podman_images < <(podman_images_of "${layout_images[@]}" "${dnf_images[@]}")
  make_images "${podman_images[@]}"
  if [[ $(build_info source-archives) == yes ]]; then
    title "source archives"
    source_archives
  fi
  [[ -z $all ]] || step_made complete
}

# Prepare the sources the targets are built from, ahead of a run (run
# prepares them when it needs them). Uses the current build's tools image.
cmd_prepare() {
  local p s
  local -a args=("$@")
  local -A seen=()
  id=$(current_id) || die "no current build; start one with run --new"
  bdir=$builds/$id
  PIPELINE=$(build_info pipeline)
  PIPELINE=${PIPELINE:-pos}
  title_init
  ((${#args[@]})) || mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  for p in "${TARGETS[@]}"; do
    p=$(build_of "$p")
    for s in ${SRC[$p]} ${WSRC[$p]}; do
      [[ -z ${seen[$s]:-} ]] && has_prepare "$s" || continue
      seen[$s]=1
      prepare_source "$s"
      echo "$s: $PREPARED"
    done
  done
}

# The RPM packages of the assembled stages of the current build
# (buildsys/rpm.sh).
cmd_rpm() {
  local s
  local -a args=("$@")
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  ((${#args[@]})) || mapfile -t args < <(all_stages)
  for s in "${args[@]}"; do
    [[ -f $base/stages/$s/packages ]] || die "not a stage: $s"
    [[ -f $bdir/pos-$s-$(build_stem "$bdir").tar.zst ]] || die "stage $s is not assembled in build $id; run it first"
  done
  rpm_make "${args[@]}"
}

# Make images of the current build again (default: all); a dnf image
# takes the RPM packages ./build rpm made, a podman image the image it is
# made from.
cmd_image() {
  local t
  [[ ${1:-} != --no-checks ]] || { CHECKS=no; shift; }
  local -a args=("$@")
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  if ((${#args[@]} == 0)); then
    for t in "$base"/images/*/; do
      args+=("$(basename "$t")")
    done
  fi
  for t in "${args[@]}"; do
    [[ -f $base/images/$t/layout || -f $base/images/$t/packages || -f $base/images/$t/containerfile ]] ||
      die "not an image: $t"
  done
  make_images "${args[@]}"
}

cmd_rebuild() {
  local p q
  (($#)) || usage
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  for p in "$@"; do
    case ${KIND[$p]:-} in
      package) ;;
      output) die "$p is an output of ${PARENT[$p]}; rebuild ${PARENT[$p]}" ;;
      *) die "not a package: $p" ;;
    esac
    for q in "$p" ${OUTS[$p]}; do
      rm -rf "${bdir:?}/dest/$q" "${bdir:?}/debug/$q" "${bdir:?}/made/package-$q"
      echo "$q: dropped from build $id"
    done
  done
  # What was made from the packages is made again by run.
  find "$bdir/made" -mindepth 1 -maxdepth 1 ! -name 'package-*' -delete 2>/dev/null || true
}

cmd_status() {
  local p
  local -a built=()
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  cat "$bdir/info"
  build_load
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] && built+=("$p")
  done
  echo "built (${#built[@]}): ${built[*]}"
  local -a args
  mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  wanted "${TARGETS[@]}"
  echo "pending (${#WANTED[@]}): ${WANTED[*]}"
}

cmd_clean() {
  id=${1:-$(current_id)} || die "no current build"
  if host_podman image exists "localhost/pos-tools:$id"; then
    echo "removing image localhost/pos-tools:$id"
    host_podman rmi "localhost/pos-tools:$id" >/dev/null
  fi
  rm -rf "${builds:?}/$id/roots"
  echo "outputs are kept in $builds/$id"
}

# Store a complete toolchain build in the reference store (reference-dir)
# and mark it the default reference of new builds. The archive holds the
# build's info and the staging trees and debug info of what it built: the
# toolchain packages, and what they run on (glibc), which a pos build uses
# while it builds its own.
cmd_reference() {
  local store out p t
  local -a trees=() debug=()
  id=${1:-$(current_id)} || die "no current build"
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  [[ $(build_info pipeline) == toolchain ]] || die "build $id is not a toolchain build; only those are references"
  PIPELINE=toolchain
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference-dir is not set (build.conf.dist)"
  [[ -d $store ]] || die "reference-dir $store does not exist"
  load_built
  local -a args
  mapfile -t args < <(pipeline_targets)
  targets_expand "${args[@]}"
  for t in "${TARGETS[@]}"; do
    [[ -n ${BUILT[$t]:-} ]] || die "build $id is not complete: $t is not built"
  done
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] || continue
    trees+=("dest/$p")
    [[ ! -d $bdir/debug/$p ]] || debug+=("debug/$p")
  done
  out=$store/pos-ref-$id.tar.zst
  if [[ ! -f $out ]]; then
    tar --zstd -cf "$out.tmp" -C "$bdir" info "${trees[@]}" "${debug[@]}"
    mv "$out.tmp" "$out"
  fi
  echo "$id" >"$store/default"
  echo "$out (${#trees[@]} packages), the default reference"
}

# The BUILD number in VERSION at a commit, or nothing; version_update the
# same for UPDATE, which only a release line has.
version_build() {
  { git -C "$base" show "$1:VERSION" 2>/dev/null || true; } | sed -n 's/^BUILD=\([0-9][0-9]*\)$/\1/p'
}

version_update() {
  { git -C "$base" show "$1:VERSION" 2>/dev/null || true; } | sed -n 's/^UPDATE=\([0-9][0-9]*\)$/\1/p'
}

# The info lines naming a build made at a commit (buildinfo.sh): its BUILD,
# UPDATE and version, <BUILD> or <BUILD>u<UPDATE>. None without VERSION.
version_info() {
  local n u
  n=$(version_build "$1")
  u=$(version_update "$1")
  [[ -n $n ]] || return 0
  echo "build-number $n"
  [[ -z $u ]] || echo "update $u"
  echo "version $n${u:+u$u}"
}

# Check that build id is an OS build (BUILD.md "Build numbers"): a pos
# build with a complete run, whose every record (step_made) was made from
# its commit, clean, with its checks unless unchecked is yes; its BUILD
# (VERSION at that commit) above every main-* tag. Lists every problem and
# exits, or sets BUILD_NUMBER and UNCHECKED (the records made unchecked).
validate() {
  local unchecked=$1 commit f r last
  local -a problems=()
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  commit=$(build_info commit)
  UNCHECKED=()
  [[ $(build_info pipeline) == pos ]] || problems+=("not a pos build")
  [[ -f $bdir/made/complete ]] || problems+=("no complete run since it was created or last rebuilt")
  for f in "$bdir"/made/*; do
    [[ -f $f ]] || continue
    r=$(<"$f")
    case $r in
      "$commit clean") ;;
      "$commit clean unchecked")
        UNCHECKED+=("$(basename "$f")")
        [[ $unchecked == yes ]] || problems+=("$(basename "$f"): made without its checks (--unchecked accepts it)") ;;
      *) problems+=("$(basename "$f"): made from $r, not $commit clean") ;;
    esac
  done
  BUILD_NUMBER=$(version_build "$commit")
  if [[ -z $BUILD_NUMBER ]]; then
    problems+=("no BUILD in VERSION at $commit")
  else
    last=$(git -C "$base" tag -l 'main-*' | sed -n 's/^main-\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1)
    ((BUILD_NUMBER > ${last:-0})) || problems+=("BUILD $BUILD_NUMBER is not above the last tag, main-$last")
  fi
  if ((${#problems[@]})); then
    echo "build $id is not an OS build:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 1
  fi
}

# The checks of a validated build, for messages and the tag.
checks_said() {
  if ((${#UNCHECKED[@]})); then
    echo "checks skipped: ${UNCHECKED[*]}"
  else
    echo "checks passed"
  fi
}

cmd_validate() {
  local unchecked=no
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# <= 1)) || usage
  id=${1:-$(current_id)} || die "no current build"
  validate "$unchecked"
  echo "build $id is BUILD $BUILD_NUMBER (commit $(build_info commit), $(checks_said))"
}

# Number the current build: tag its commit main-<BUILD>, with the build ID
# in the tag, then bump. HEAD is on main and has not been bumped since the
# build's commit, so the next BUILD follows this one.
cmd_tag() {
  local unchecked=no commit
  [[ ${1:-} != --unchecked ]] || { unchecked=yes; shift; }
  (($# == 0)) || usage
  [[ $(git -C "$base" symbolic-ref --short HEAD 2>/dev/null) == main ]] || die "tag numbers builds of main; check out main"
  # The tagger is whoever numbers the build: git's identity here.
  git -C "$base" var GIT_COMMITTER_IDENT >/dev/null 2>&1 ||
    die "git has no identity for the tagger; set user.name and user.email (git config)"
  id=$(current_id) || die "no current build"
  validate "$unchecked"
  commit=$(build_info commit)
  git -C "$base" merge-base --is-ancestor "$commit" HEAD || die "build $id: $commit is not on main"
  [[ $(version_build HEAD) == "$BUILD_NUMBER" ]] ||
    die "VERSION at HEAD is BUILD $(version_build HEAD), build $id is BUILD $BUILD_NUMBER; bumped since?"
  git -C "$base" tag -a "main-$BUILD_NUMBER" -m "POS BUILD $BUILD_NUMBER

build $id
reference $(build_info reference)
$(checks_said)" "$commit"
  echo "tagged $commit main-$BUILD_NUMBER"
  cmd_bump
}

# Commit VERSION with the next BUILD. tag runs it after tagging; run it
# alone when tag failed after the tag was made.
cmd_bump() {
  local n
  (($# == 0)) || usage
  git -C "$base" diff --quiet HEAD -- VERSION || die "VERSION has uncommitted changes"
  n=$(version_build HEAD)
  [[ -n $n ]] || die "no BUILD in VERSION at HEAD"
  sed -i "s/^BUILD=$n\$/BUILD=$((n + 1))/" "$base/VERSION"
  GIT_COMMITTER_NAME=$bot_name GIT_COMMITTER_EMAIL=$bot_email \
    git -C "$base" commit -q --author="$bot_name <$bot_email>" -m "BUILD $((n + 1)) is next" -- VERSION
  echo "VERSION: BUILD $((n + 1))"
}

meta_load
meta_validate || die "invalid package metadata"

cmd=${1:-}
(($#)) && shift
case $cmd in
  plan) cmd_plan "$@" ;;
  run) cmd_run "$@" ;;
  prepare) cmd_prepare "$@" ;;
  rebuild) cmd_rebuild "$@" ;;
  rpm) cmd_rpm "$@" ;;
  image) cmd_image "$@" ;;
  status) cmd_status ;;
  reference) cmd_reference "$@" ;;
  clean) cmd_clean "$@" ;;
  validate) cmd_validate "$@" ;;
  tag) cmd_tag "$@" ;;
  bump) cmd_bump "$@" ;;
  *) usage ;;
esac
