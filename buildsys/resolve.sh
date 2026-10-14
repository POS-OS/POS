#!/usr/bin/env bash
# Package metadata and dependency resolution. Sourced by buildsys/build.sh.
#
# Every directory in packages/ has a meta file of "key value..." lines.
# Repeated keys accumulate; # starts a comment.
#
#   requires        capabilities needed at run time; installed with the
#                   package, so they are part of every build that uses it
#   build-requires  capabilities needed only to build the package
#   host-requires   Fedora packages dnf installs into the build toolbox
#   prepare-requires  Fedora packages for preparing the package's source
#                   (packages/<source>/prepare.sh) in the prepare toolbox
#   provides        extra capabilities; every package provides its own name
#   obsoletes       packages this one replaces. Where both are available,
#                   the obsoleting package is the one chosen
#   source          tree under src/ (default: the package name); its
#                   prepare recipe is packages/<source>/prepare.sh
#   with-sources    further source trees the build copies into its own,
#                   each as a directory named after the source (gcc builds
#                   gmp, mpfr and mpc in its tree)
#   outputs         further packages the build produces (kind output)
#   output-of       the package whose build produces this one
#   pipeline        pos (default) or toolchain: the build that builds the
#                   package (see below). An output is in its main
#                   package's pipeline
#   kind            package (default): built by build.sh
#                   output: produced by another package's build; installed
#                   and released like a package, never built on its own
#                   host: nothing to build; stands for the host-requires
#                   installed by dnf
#                   profile: nothing to build or install; a build setup
#                   that recipes require
#                   source: nothing to build; holds the prepare recipe of
#                   a source other packages build from (with-sources)
#
# A package directory may also have env.sh. pkg_setup sources it in every
# build whose resolved environment contains the package.
#
# A capability is satisfied by any available package that provides it: a
# package or output built in the current build, or a host or profile
# package. When several are
# available, those obsoleted by another candidate are dropped; more than one
# left is an error.
#
# A build is in one of two pipelines (PIPELINE). A toolchain build builds
# the toolchain packages and what they need at run time. A pos build
# builds everything else and never builds a toolchain package: those are
# its reference's. A host or profile package that a reference package
# obsoletes is not available: gcc-host, Fedora's compiler, stands in for
# gcc only in a build without a reference.
#
# A build with a reference build (REF: the packages built in it) falls
# back to the reference's copy of a package when nothing available
# provides a capability, if the capability is a stand-in one (provided by
# a package another obsoletes: the reference's gcc stands in for
# gcc-host), or, in a pos build, if no target of the run provides it (it
# is not being built). In ENV it is <name>@ref. Its own requirements are
# those it was built with (REF_REQ), and are met by this build's packages
# where they are built, otherwise by the reference's, whether or not they
# are targets: the reference's gcc builds glibc, which gcc itself
# requires.

declare -a PKGS=()
declare -A KIND=() REQ=() BREQ=() HREQ=() PREQ=() PROV=() OBS=() SRC=() WSRC=() OUTS=() PARENT=()
declare -A PIPE=()
declare -A PROVIDERS=() BOOTCAP=() TPROV=()
declare -A BUILT=() REF=() REF_REQ=()
PIPELINE=pos

die() {
  echo "$*" >&2
  exit 1
}

meta_load() {
  local dir p key vals line
  for dir in "$base"/packages/*/; do
    p=$(basename "$dir")
    [[ -f $dir/meta ]] || die "packages/$p: missing meta"
    PKGS+=("$p")
    KIND[$p]=package REQ[$p]= BREQ[$p]= HREQ[$p]= PREQ[$p]= PROV[$p]=$p OBS[$p]= SRC[$p]=$p
    WSRC[$p]= OUTS[$p]= PARENT[$p]= PIPE[$p]=pos
    while read -r line; do
      line=${line%%#*}
      read -r key vals <<<"$line"
      [[ -z $key ]] && continue
      case $key in
        requires) REQ[$p]+=" $vals" ;;
        build-requires) BREQ[$p]+=" $vals" ;;
        host-requires) HREQ[$p]+=" $vals" ;;
        prepare-requires) PREQ[$p]+=" $vals" ;;
        provides) PROV[$p]+=" $vals" ;;
        obsoletes) OBS[$p]+=" $vals" ;;
        source) SRC[$p]=$vals ;;
        with-sources) WSRC[$p]+=" $vals" ;;
        pipeline) PIPE[$p]=$vals ;;
        kind) KIND[$p]=$vals ;;
        outputs) OUTS[$p]+=" $vals" ;;
        output-of) PARENT[$p]=$vals ;;
        *) die "packages/$p/meta: unknown key: $key" ;;
      esac
    done <"$dir/meta"
    if [[ ${KIND[$p]} == package ]]; then
      # Everything built gets the common host tools.
      BREQ[$p]+=" host-base"
    fi
  done
  local cap q
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} != output ]] || PIPE[$p]=${PIPE[${PARENT[$p]}]:-pos}
    for cap in ${PROV[$p]}; do
      PROVIDERS[$cap]+=" $p"
    done
    for q in ${OBS[$p]}; do
      for cap in ${PROV[$q]:-}; do
        BOOTCAP[$cap]=1
      done
    done
  done
}

meta_validate() {
  local p cap q err=0
  local -A required=()
  for p in "${PKGS[@]}"; do
    case ${KIND[$p]} in
      package) [[ -x $base/packages/$p/build.sh ]] || { echo "packages/$p: missing executable build.sh" >&2; err=1; } ;;
      output)
        q=${PARENT[$p]}
        if [[ ${KIND[$q]:-} != package || " ${OUTS[$q]} " != *" $p "* ]]; then
          echo "packages/$p/meta: output-of $q, which does not list it in outputs" >&2
          err=1
        fi
        ;;
      host|profile|source) ;;
      *) echo "packages/$p/meta: unknown kind: ${KIND[$p]}" >&2; err=1 ;;
    esac
    for cap in ${REQ[$p]} ${BREQ[$p]}; do
      required[$cap]=1
      if [[ -z ${PROVIDERS[$cap]:-} ]]; then
        echo "packages/$p/meta: nothing provides $cap" >&2
        err=1
      fi
    done
    case ${PIPE[$p]} in
      pos|toolchain) ;;
      *) echo "packages/$p/meta: unknown pipeline: ${PIPE[$p]}" >&2; err=1 ;;
    esac
    for q in ${WSRC[$p]}; do
      if [[ ! -d $base/src/$q ]]; then
        echo "packages/$p/meta: with-sources $q: no src/$q" >&2
        err=1
      fi
    done
    for q in ${OUTS[$p]}; do
      if [[ ${KIND[$q]:-} != output || ${PARENT[$q]} != "$p" ]]; then
        echo "packages/$p/meta: output $q is not kind output with output-of $p" >&2
        err=1
      fi
    done
    for q in ${OBS[$p]}; do
      if [[ -z ${KIND[$q]:-} ]]; then
        echo "packages/$p/meta: obsoletes unknown package $q" >&2
        err=1
      fi
    done
  done
  # An obsoleting package takes over every capability that the obsoleted
  # one is required for; otherwise preferring it would leave those unmet.
  for p in "${PKGS[@]}"; do
    for q in ${OBS[$p]}; do
      [[ -n ${KIND[$q]:-} ]] || continue
      for cap in ${PROV[$q]}; do
        if [[ -n ${required[$cap]:-} && " ${PROV[$p]} " != *" $cap "* ]]; then
          echo "packages/$p/meta: obsoletes $q but does not provide $cap" >&2
          err=1
        fi
      done
    done
  done
  return $err
}

# Built packages, and host and profile packages that no reference package
# obsoletes.
available() {
  case ${KIND[$1]} in
    host|profile) ! obsoleted_by_any "$1" "${!REF[@]}" ;;
    *) [[ -n ${BUILT[$1]:-} ]] ;;
  esac
}

# Whether the build's pipeline builds a package.
in_pipeline() {
  [[ ${PIPE[$1]} == "$PIPELINE" ]]
}

# The package whose build produces p.
build_of() {
  if [[ ${KIND[$1]} == output ]]; then
    echo "${PARENT[$1]}"
  else
    echo "$1"
  fi
}

# Capabilities a build provides: the package's and its outputs'.
self_provides() {
  local p=$1 o
  echo "${PROV[$p]}"
  for o in ${OUTS[$p]}; do
    echo "${PROV[$o]}"
  done
}

# True when one of the packages q (or, for builds, their outputs) obsoletes p.
obsoleted_by_any() {
  local p=$1 q o
  shift
  for q in "$@"; do
    [[ $q == "$p" ]] && continue
    for o in "$q" ${OUTS[$q]:-}; do
      [[ " ${OBS[$o]} " == *" $p "* ]] && return 0
    done
  done
  return 1
}

# Set PROVIDER to the available provider of a capability. Returns 1 when
# none is available. Dies when the choice is ambiguous. With ref, the
# capability is a requirement of a reference package (see the top).
provider() {
  local cap=$1 ref=${2:-} p
  local -a cands=() chosen=()
  for p in ${PROVIDERS[$cap]:-}; do
    available "$p" && cands+=("$p")
  done
  for p in "${cands[@]}"; do
    obsoleted_by_any "$p" "${cands[@]}" || chosen+=("$p")
  done
  case ${#chosen[@]} in
    0) provider_ref "$cap" "$ref" ;;
    1) PROVIDER=${chosen[0]} ;;
    *) die "ambiguous providers of $cap: ${chosen[*]} (add obsoletes to pick one)" ;;
  esac
}

# The reference's copy of a provider, as PROVIDER=<name>@ref (see the top).
provider_ref() {
  local cap=$1 ref=$2 p
  [[ -n $ref || -n ${BOOTCAP[$cap]:-} ]] ||
    [[ $PIPELINE == pos && -z ${TPROV[$cap]:-} ]] || return 1
  for p in ${PROVIDERS[$cap]:-}; do
    if [[ -n ${REF[$p]:-} ]]; then
      PROVIDER=$p@ref
      return 0
    fi
  done
  return 1
}

is_ref() {
  [[ $1 == *@ref ]]
}

# Resolve the build environment of a package: its requirements and,
# recursively, the run-time requirements of each provider chosen. A
# requirement the build itself provides (gcc requires its own output
# gcc-runtime) is installed with the package, not needed to build it.
# Reached through another package's requirements, it is needed (systemd
# links util-linux's libmount, which links libsystemd), and the reference's
# copy is used, as in a new build, where the package is not built yet. Sets
# ENV (sorted package names) and MISSING (capabilities with no available
# provider). Returns 1 when anything is missing.
env_of() {
  local p=$1 cap entry ref q
  local -a queue=()
  local -A seen=() inenv=()
  local self
  self=" $(self_provides "$p" | xargs) "
  for cap in ${BREQ[$p]} ${REQ[$p]}; do
    [[ $self == *" $cap "* ]] || queue+=("$cap")
  done
  ENV=() MISSING=()
  # An entry is a capability, or ref:<capability> for a requirement of a
  # reference package.
  while ((${#queue[@]})); do
    entry=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -n ${seen[$entry]:-} ]] && continue
    seen[$entry]=1
    cap=${entry#ref:}
    ref=
    [[ $entry == ref:* || $self == *" $cap "* ]] && ref=1
    if ! provider "$cap" "$ref"; then
      MISSING+=("$cap")
      continue
    fi
    [[ -n ${inenv[$PROVIDER]:-} ]] && continue
    inenv[$PROVIDER]=1
    if is_ref "$PROVIDER"; then
      for q in ${REF_REQ[${PROVIDER%@ref}]:-}; do
        queue+=("ref:$q")
      done
    else
      queue+=(${REQ[$PROVIDER]})
    fi
  done
  mapfile -t ENV < <(printf '%s\n' "${!inenv[@]}" | sed '/^$/d' | sort)
  ((${#MISSING[@]} == 0))
}

env_provides() {
  local cap=$1 p
  for p in "${ENV[@]}"; do
    [[ " ${PROV[${p%@ref}]} " == *" $cap "* ]] && return 0
  done
  return 1
}

# Packages in the environment that set up the build (buildsys/pkg.sh).
env_scripts() {
  local p
  for p in "${ENV[@]}"; do
    p=${p%@ref}
    [[ -f $base/packages/$p/env.sh ]] && echo "$p"
  done
  return 0
}

# Expand target names (stages or packages) into TARGETS (package names),
# and TPROV, the capabilities their builds provide. A pos build leaves out
# the toolchain packages of a stage, which its reference has; a toolchain
# build has toolchain packages only.
targets_expand() {
  local t p
  local -A set=()
  for t in "$@"; do
    if [[ -f $base/stages/$t/packages ]]; then
      [[ $PIPELINE == pos ]] || die "$t: a toolchain build builds toolchain packages, not stages"
      while read -r p; do
        p=${p%%#*}
        p=${p//[[:space:]]/}
        [[ -z $p ]] && continue
        case ${KIND[$p]:-} in
          package|output) ;;
          '') die "stages/$t/packages: unknown package $p" ;;
          *) die "stages/$t/packages: $p is not a package (kind ${KIND[$p]})" ;;
        esac
        in_pipeline "$p" && set[$p]=1
      done <"$base/stages/$t/packages"
    elif [[ -n ${KIND[$t]:-} ]]; then
      in_pipeline "$t" || die "$t: a ${PIPE[$t]} package; this is a $PIPELINE build"
      set[$t]=1
    else
      die "unknown stage or package: $t"
    fi
  done
  mapfile -t TARGETS < <(printf '%s\n' "${!set[@]}" | sed '/^$/d' | sort)
  TPROV=()
  for t in "${TARGETS[@]}"; do
    for p in $(self_provides "$(build_of "$t")"); do
      TPROV[$p]=1
    done
  done
}

all_stages() {
  local d
  for d in "$base"/stages/*/; do
    [[ -f $d/packages ]] && basename "$d"
  done
  return 0
}

# What a build of the pipeline builds by default: every stage, or every
# toolchain package.
pipeline_targets() {
  local p
  if [[ $PIPELINE == pos ]]; then
    all_stages
    return 0
  fi
  for p in "${PKGS[@]}"; do
    [[ ${KIND[$p]} == package ]] && in_pipeline "$p" && echo "$p"
  done
  return 0
}

# Warn about run-time requirements that nothing in the target set, or the
# toolchain a pos build takes from its reference, provides: the released
# archives would not be complete.
targets_check() {
  local p cap q found
  for p in "$@"; do
    for cap in ${REQ[$p]}; do
      found=
      for q in "$@"; do
        [[ " ${PROV[$q]} " == *" $cap "* ]] && { found=1; break; }
      done
      for q in ${PROVIDERS[$cap]:-}; do
        [[ ${PIPE[$q]} == toolchain ]] && found=1
      done
      [[ -n $found ]] || echo "warning: $p requires $cap, which no target provides" >&2
    done
  done
  return 0
}

# Packages that must be built for the targets: the targets themselves and
# every provider of a capability that has no available provider yet.
# Sets WANTED (sorted).
wanted() {
  local -A want=()
  local p cap q o b self changed=1
  for p in "$@"; do
    available "$p" || want[$(build_of "$p")]=1
  done
  while ((changed)); do
    changed=0
    for p in "${!want[@]}"; do
      self=" $(self_provides "$p" | xargs) "
      local -a caps=(${BREQ[$p]} ${REQ[$p]})
      for o in ${OUTS[$p]}; do
        caps+=(${REQ[$o]})
      done
      while ((${#caps[@]})); do
        cap=${caps[0]}
        caps=("${caps[@]:1}")
        [[ $self == *" $cap "* ]] && continue
        if provider "$cap"; then
          # A profile or host package is not built, so what it requires
          # is needed by the package that requires it.
          [[ ${KIND[$PROVIDER]:-} == host || ${KIND[$PROVIDER]:-} == profile ]] && caps+=(${REQ[$PROVIDER]})
          continue
        fi
        for q in ${PROVIDERS[$cap]:-}; do
          b=$(build_of "$q")
          # Only packages are built, and a pos build does not build the
          # toolchain; a toolchain build builds what the toolchain needs.
          [[ ${KIND[$b]} == package ]] || continue
          [[ $PIPELINE == pos && ${PIPE[$b]} == toolchain ]] && continue
          if [[ -z ${want[$b]:-} ]] && ! available "$q"; then
            want[$b]=1
            changed=1
          fi
        done
      done
    done
  done
  mapfile -t WANTED < <(printf '%s\n' "${!want[@]}" | sed '/^$/d' | sort)
}

# Set NEXT to the next package to build: a wanted package whose environment
# resolves. A candidate obsoleted by another buildable candidate waits, so
# the replacement is built instead of the bootstrap package. Returns 1 when
# nothing can be built.
next_package() {
  local p
  local -a ready=()
  wanted "$@"
  for p in "${WANTED[@]}"; do
    env_of "$p" && ready+=("$p")
  done
  for p in "${ready[@]}"; do
    if ! obsoleted_by_any "$p" "${ready[@]}"; then
      NEXT=$p
      return 0
    fi
  done
  return 1
}
