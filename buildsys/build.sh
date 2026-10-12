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
# for it and mounted read-only. What the build does not build comes from
# its reference build (work/references/<ref>, restored from the reference
# store) or, without one, from the bootstrap packages. podman runs on the
# host; from inside a toolbox through flatpak-spawn.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=resolve.sh
source "$base/buildsys/resolve.sh"
# shellcheck source=config.sh
source "$base/buildsys/config.sh"

builds=$base/work/builds
sources=$base/work/sources
refs=$base/work/references
fedora_release=$(config fedora-release)
fedora_image=registry.fedoraproject.org/fedora
export LC_ALL=C

usage() {
  cat >&2 <<EOF
usage: ./build plan [--new] [<target>...]      print what run would build, in order
       ./build run [--new [--source-archives]] [<target>...]
                                               build the targets, then assemble stage
                                               archives and images
       ./build prepare [<target>...]           prepare the sources of the targets now
       ./build rebuild <package>...            drop packages from the current build
       ./build rpm [<stage>...]                make RPM packages of the current build
       ./build image [<image>...]              make images of the current build again
       ./build status                          show the current build
       ./build reference [<id>]                store a complete build as the
                                               default reference
       ./build clean [<id>]                    remove the tools image of a build

A target is a stage (stages/<stage>/packages) or a package. The default is
every stage. run continues the current build; --new starts another. An
image (images/<image>/layout) is made when run assembles all its stages;
one made with dnf (images/<image>/packages) when run assembles all
stages, after the RPM packages; one made with podman
(images/<image>/containerfile) after the image it is made from.
--source-archives makes the new build also write an archive of every
source it built from (pos-src-<source>-<key>.tar.zst) and of the build
recipes (pos-recipes-<id>.tar.zst).

A new build takes what it does not build from a reference build, by
default the one reference marked last, or builds the bootstrap packages
without one. Settings (build.conf.dist) are read from
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
# declares, and rpm-build for the RPM packages (buildsys/rpm.sh).
tools_packages() {
  local p
  {
    for p in "${PKGS[@]}"; do
      echo ${HREQ[$p]} ${PREQ[$p]}
    done
    echo rpm-build
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
# they were built with (resolve.sh: REF, REF_REQ).
load_reference() {
  local ref=$1 meta p
  REF=() REF_REQ=()
  [[ $ref != none ]] || return 0
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
  local archives=${1:-no} ref from
  id=$(date +%Y%m%d%H%M)
  [[ ! -e $builds/$id ]] || die "build $id already exists; wait a minute"
  ref=$(reference_choose)
  reference_restore "$ref"
  from=$(tools_base)
  bdir=$builds/$id
  mkdir -p "$bdir"/{dest,debug,build,logs}
  tools_build "$from"
  {
    echo "id $id"
    echo "fedora $fedora_release"
    echo "tools-base $from"
    echo "tools-image localhost/pos-tools:$id"
    echo "reference $ref"
    echo "branch $(git -C "$base" rev-parse --abbrev-ref HEAD)"
    echo "commit $(git -C "$base" rev-parse HEAD)"
    echo "started $(date -u +%FT%TZ)"
    echo "source-archives $archives"
  } >"$builds/$id/info"
  ln -sfn "$id" "$builds/current"
  echo "$id"
}

build_info() {
  awk -v k="$1" '$1 == k {print $2}' "$bdir/info"
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
  local s=$1
  {
    source_tree "$s"
    upstream_info "$s"
    cat "$base/packages/$s/prepare.sh" "$base/buildsys/prepare.sh"
    echo "${PREQ[$s]}"
    if [[ -f $base/src/$s/bootstrap.conf || -x $base/src/$s/autopull.sh ]]; then
      source_tree gnulib
    fi
  } | sha256sum | cut -c1-16
}

# Prepare a source unless a tree with the same key exists. Sets PREPARED to
# the prepared tree. Prepare has network: it fetches what upstream's
# release process does. It sees the committed source (prepare recipes
# compare with it), and src/gnulib.
prepare_source() {
  local s=$1 key dir log hbase
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
  title "prepare $s"
  echo "=== prepare $s ($key) ===" | tee "$log"
  step_run "prepare-$s" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_SOURCE="$s" \
    POS_PREP_DIR="$(host_path "$dir.tmp")" \
    POS_UPSTREAM="$(host_path "$dir.upstream")" \
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
  local p=$1 dest=$bdir/dest/$1 dir extra
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
    echo "build-env ${ENV[*]}"
    echo "build-tools $TOOLS_ID"
    echo "build-reference $(build_reference)"
    echo "built $(date -u +%FT%TZ)"
  } >"$dir/meta.tmp"
  mv "$dir/meta.tmp" "$dir/meta"
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
# unless given net (network) or root (the container's root, which is the
# caller outside it).
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
      root) user= ;;
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

build_one() {
  local p=$1 q scripts log root
  env_of "$p" || die "$p: unresolved: ${MISSING[*]}"
  scripts=$(env_scripts | xargs)
  log=$bdir/logs/$p.log
  root=$bdir/roots/$p
  local hbase hbdir src_dir s=${SRC[$p]}
  hbase=$(host_path "$base")
  hbdir=$(host_path "$bdir")
  # The source a package is built from, and its identity for the package
  # metadata and the source archives: the prepared tree's key, or the
  # committed tree.
  if has_prepare "$s"; then
    prepare_source "$s"
    src_dir=$PREPARED
    SOURCE_ID=$(basename "$PREPARED")
  elif [[ -d $base/src/$s ]]; then
    src_dir=$base/src/$s
    SOURCE_ID=$(source_tree "$s")
  else
    src_dir=$base/src/$s
    SOURCE_ID=
  fi

  # The package's own inputs: the recipes (they source each other's),
  # its source tree, and the build's build, dest and debug directories.
  local -a mounts=(pos:"$root" ro:"$base/buildsys" ro:"$base/packages")
  [[ ! -d $src_dir ]] || mounts+=(ro:"$src_dir")
  mounts+=(rw:"$bdir/build" rw:"$bdir/dest" rw:"$bdir/debug")

  echo "=== $p: setup: ${scripts:-none} ===" | tee "$log"
  echo "env: ${ENV[*]}" | tee -a "$log"
  root_compose "$root"
  step_run "$p" "${mounts[@]}" -- env \
    POS_BASE="$hbase" \
    POS_PACKAGE="$p" \
    POS_SRC_DIR="$(host_path "$src_dir")" \
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
  local id= bdir n=0 t
  local -a args=()
  for t in "$@"; do
    case $t in
      --new) id="<new>" ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  local ref
  if [[ -z $id ]] && id=$(current_id); then
    bdir=$builds/$id
    load_built
    ref=$(build_reference)
  else
    id="<new>"
    ref=$(reference_choose)
  fi
  reference_restore "$ref"
  load_reference "$ref"
  ((${#args[@]})) || mapfile -t args < <(all_stages)
  targets_expand "${args[@]}"
  targets_check "${TARGETS[@]}"
  echo "build $id"
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
# their metadata (build-source), and the build recipes.
source_archives() {
  local p s key out commit
  local -A seen=()
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package && -n ${BUILT[$p]:-} ]] || continue
    s=${SRC[$p]}
    [[ -z ${seen[$s]:-} ]] || continue
    seen[$s]=1
    key=$(awk '$1 == "build-source" {print $3}' "$(marker "$p")")
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
  done
  commit=$(git -C "$base" rev-parse HEAD)
  if [[ $commit != "$(build_info commit)" ]] ||
     [[ -n $(git -C "$base" status --porcelain --untracked-files=no -- buildsys packages stages images rpm) ]]; then
    echo "warning: buildsys, packages, stages, images or rpm differ from the commit the build started at;" \
         "the recipes archive holds HEAD" >&2
  fi
  out=$bdir/pos-recipes-$id.tar.zst
  git -C "$base" archive --format=tar --prefix="pos-recipes-$id/" HEAD \
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
    --change "LABEL pos.build=$id" \
    "$(host_path "$bdir/pos-image-$t-$id.tar.zst")" "$(podman_name "$t"):$id"
}

# Make an image with podman from images/<image>/containerfile, on top of
# the build's image named in images/<image>/from (BASE). It is tagged
# with the build ID and with the Fedora release, the tag a new build
# looks for.
podman_image() {
  local t=$1 from name
  from=$(image_from "$t")
  [[ -f $bdir/pos-image-$from-$id.tar.zst ]] || die "$t: build $id has no $from image; make it first"
  podman_import "$from"
  name=localhost/$(podman_name "$t")
  host_podman build --build-arg "BASE=localhost/$(podman_name "$from"):$id" \
    --label "pos.build=$id" -t "$name:$id" \
    -f "$(host_path "$base/images/$t/containerfile")" "$(host_path "$base/images/$t")"
  host_podman tag "$name:$id" "$name:$(build_info fedora)"
  echo "$name:$id"
}

# Make the RPM packages of the given stages (buildsys/rpm.sh). It needs
# network: pos-fedora takes the provides of the Fedora packages it stands
# in for from Fedora's repositories.
rpm_make() {
  step_run rpm net ro:"$base/buildsys" ro:"$base/stages" ro:"$base/rpm" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/rpm.sh")" "$(host_path "$bdir")" "$@"
}

# Make an image with dnf (buildsys/image-dnf.sh), as root: dnf installs
# files owned by the users packages create. It needs network for Fedora's
# repositories.
dnf_image() {
  step_run "image-$1" net root ro:"$base/buildsys" ro:"$base/images" rw:"$bdir" -- \
    bash "$(host_path "$base/buildsys/image-dnf.sh")" "$(host_path "$bdir")" "$1"
}

# Make the images of the given names: layout images from the stage
# archives, dnf images from the RPM packages, podman images from another
# image.
make_images() {
  local t
  for t in "$@"; do
    title "image $t"
    if [[ -f $base/images/$t/layout ]]; then
      "$base/buildsys/image.sh" "$bdir" "$t"
    elif [[ -f $base/images/$t/packages ]]; then
      dnf_image "$t"
    else
      podman_image "$t"
    fi
  done
}

cmd_run() {
  local new= archives=no t
  local -a args=() stages=()
  for t in "$@"; do
    case $t in
      --new) new=1 ;;
      --source-archives) archives=yes ;;
      -*) usage ;;
      *) args+=("$t") ;;
    esac
  done
  ((${#args[@]})) || mapfile -t args < <(all_stages)
  targets_expand "${args[@]}"
  targets_check "${TARGETS[@]}"

  if [[ $archives == yes && -z $new ]]; then
    die "--source-archives is chosen when a build is created; use it with --new"
  fi
  if [[ -n $new ]] || ! id=$(current_id); then
    id=$(build_new "$archives")
    echo "new build $id"
  fi
  bdir=$builds/$id
  [[ -n $(build_info tools-image) ]] ||
    die "build $id builds in toolboxes, which this buildsys no longer does; start another with run --new"
  load_built
  reference_restore "$(build_reference)"
  load_reference "$(build_reference)"
  echo "reference $(build_reference) (${#REF[@]} packages)"
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
    "$base/buildsys/assemble.sh" "$bdir" "$t"
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
}

# Prepare the sources the targets are built from, ahead of a run (run
# prepares them when it needs them). Uses the current build's tools image.
cmd_prepare() {
  local p s
  local -a args=("$@")
  local -A seen=()
  id=$(current_id) || die "no current build; start one with run --new"
  bdir=$builds/$id
  title_init
  ((${#args[@]})) || mapfile -t args < <(all_stages)
  targets_expand "${args[@]}"
  for p in "${TARGETS[@]}"; do
    s=${SRC[$(build_of "$p")]}
    [[ -z ${seen[$s]:-} ]] && has_prepare "$s" || continue
    seen[$s]=1
    prepare_source "$s"
    echo "$s: $PREPARED"
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
    [[ -f $bdir/pos-$s-$id.tar.zst ]] || die "stage $s is not assembled in build $id; run it first"
  done
  rpm_make "${args[@]}"
}

# Make images of the current build again (default: all); a dnf image
# takes the RPM packages ./build rpm made, a podman image the image it is
# made from.
cmd_image() {
  local t
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
      rm -rf "${bdir:?}/dest/$q" "${bdir:?}/debug/$q"
      echo "$q: dropped from build $id"
    done
  done
}

cmd_status() {
  local p
  local -a built=()
  id=$(current_id) || die "no current build"
  bdir=$builds/$id
  cat "$bdir/info"
  load_built
  load_reference "$(build_reference)"
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] && built+=("$p")
  done
  echo "built (${#built[@]}): ${built[*]}"
  local -a args
  mapfile -t args < <(all_stages)
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

# Store a complete build in the reference store (reference-dir) and mark
# it the default reference of new builds. The archive holds the build's
# info and the staging trees of its packages, but for the bootstrap
# packages, which a reference never stands in for.
cmd_reference() {
  local store out p t
  local -a built=() trees=()
  id=${1:-$(current_id)} || die "no current build"
  bdir=$builds/$id
  [[ -f $bdir/info ]] || die "no build $id"
  store=$(config reference-dir)
  [[ -n $store ]] || die "reference-dir is not set (build.conf.dist)"
  [[ -d $store ]] || die "reference-dir $store does not exist"
  load_built
  local -a args
  mapfile -t args < <(all_stages)
  targets_expand "${args[@]}"
  for t in "${TARGETS[@]}"; do
    [[ -n ${BUILT[$t]:-} ]] || die "build $id is not complete: $t is not built"
  done
  for p in "${PKGS[@]}"; do
    [[ -n ${BUILT[$p]:-} ]] && built+=("$p")
  done
  for p in "${built[@]}"; do
    obsoleted_by_any "$p" "${built[@]}" || trees+=("dest/$p")
  done
  out=$store/pos-ref-$id.tar.zst
  if [[ ! -f $out ]]; then
    tar --zstd -cf "$out.tmp" -C "$bdir" info "${trees[@]}"
    mv "$out.tmp" "$out"
  fi
  echo "$id" >"$store/default"
  echo "$out (${#trees[@]} packages), the default reference"
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
  *) usage ;;
esac
