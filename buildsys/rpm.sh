#!/usr/bin/env bash
# Make the RPM packages of a build. Run by buildsys/build.sh in a container
# of the build's tools image.
#
#   rpm.sh <build dir> <stage>...
#
# pos: the /pos tree of the stages other than sdk, in one package. It
#   installs nothing outside /pos and provides nothing Fedora packages
#   require, so it installs on any Fedora system.
# pos-sdk: the /pos tree of the sdk stage; requires pos of the same build.
# pos-debuginfo: the separate debug info of both, in /pos/lib/debug. Made
#   when the build has any (builds before pkg_strip have none).
# pos-fedora: requires pos and pos-sdk and stands in for the Fedora packages
#   POS replaces (rpm/fedora): it provides what they provide, links their
#   paths in /usr to /pos, and conflicts with them. On a system built with
#   it, dnf installs only what POS does not have.
#
# The packages are written to <build dir>/rpm; dnf installs them as files.
# BUILD.md "RPM packages".

set -euo pipefail
export LC_ALL=C

[[ -f /run/.containerenv && ! -f /run/.toolboxenv ]] || {
  echo "rpm.sh must run in a build container (./build rpm)" >&2
  exit 1
}

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"
bdir=${1:-}
(($# >= 2)) || {
  echo "usage: $0 <build dir> <stage>..." >&2
  exit 1
}
shift
stages=("$@")

id=$(basename "$bdir")
out=$bdir/rpm
work=$bdir/rpm-work
evr=$(rpm_evr "$bdir")
version=${evr%%-*}
release=${evr#*-}
fedora=$(rpm -E %fedora)

die() {
  echo "$*" >&2
  exit 1
}

rm -rf "$out" "$work"
mkdir -p "$out" "$work"

# The stages of each prefix package, the packages of the stages, and every
# path of the merged tree as "<type> <path>" (d directory, f file, l
# symlink).
pos_stages=()
sdk_stages=()
declare -A in_build=()
for s in "${stages[@]}"; do
  if [[ $s == sdk ]]; then sdk_stages+=("$s"); else pos_stages+=("$s"); fi
  list=$base/stages/$s/packages
  [[ -f $list ]] || die "unknown stage: $s (missing $list)"
  [[ -d $bdir/assemble/$s/pos ]] || die "stage $s is not assembled in $bdir"
  while read -r p; do
    p=${p%%#*}
    p=${p//[[:space:]]/}
    [[ -n $p ]] && in_build[$p]=1
  done <"$list"
done
((${#pos_stages[@]})) || die "no stages for pos: ${stages[*]}"
stage_paths() {
  local s
  for s in "$@"; do
    (cd "$bdir/assemble/$s" && find pos -printf '%y /%p\n')
  done | sort -u -k2,2
}
stage_paths "${stages[@]}" >"$work/paths"

# rpm expands macros and globs in a file list and splits it at spaces.
rpm_escape() {
  sed -e 's/%/%%/g' -e 's/[][*?{}\\" ]/\\&/g'
}

# The header both specs share. rpmbuild's defaults are for Fedora's /usr:
# automatic dependencies would make pos provide the sonames of Fedora's
# libraries (libc.so.6()(64bit)) and take Fedora's place without pos-fedora.
# The post-install steps strip, split debug info, add /usr/lib/.build-id
# links outside /pos, compress man pages and rewrite shebangs. POS ships
# its tree as built.
spec_head() {
  local name=$1 summary=$2
  cat <<EOF
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none
%global _binary_payload w3T0.zstdio

Name: $name
Version: $version
Release: $release
Summary: $summary
License: NOASSERTION
AutoReqProv: no
EOF
}

build_spec() {
  local spec=$1
  echo "rpm: $(basename "${spec%.spec}")"
  rpmbuild -bb --target x86_64 \
    --define "_topdir $work" \
    --define "_rpmdir $out" \
    --define "_build_name_fmt %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
    "$spec" >"${spec%.spec}.log" 2>&1 || {
    tail -n 20 "${spec%.spec}.log" >&2
    die "rpmbuild failed: ${spec%.spec}.log"
  }
  rm -rf "$work/BUILD" "$work/BUILDROOT"
}

# --- pos, pos-sdk ------------------------------------------------------

# A package of the /pos tree of stages: build_prefix <name> <summary>
# <description> <stage>... Every directory is owned, up to /pos, so removing
# the package removes the tree; the directories pos and pos-sdk share
# stay while either is installed. The stages are merged in the order given,
# as an image does.
build_prefix() {
  local name=$1 summary=$2 desc=$3 s
  shift 3
  stage_paths "$@" >"$work/$name.paths"
  {
    echo '%defattr(-,root,root,-)'
    awk '$1 == "d" {print $2}' "$work/$name.paths" | rpm_escape | sed 's|^|%dir |'
    awk '$1 != "d" {print $2}' "$work/$name.paths" | rpm_escape
  } >"$work/$name.files"

  {
    spec_head "$name" "$summary"
    [[ $name == pos ]] || echo "Requires: pos = $evr"
    cat <<EOF

%description
$desc

%install
mkdir -p %{buildroot}/pos
$(for s in "$@"; do echo "cp -a '$bdir/assemble/$s/pos/.' %{buildroot}/pos/"; done)
# Group write comes from the build directory (BUILD.md "Images").
find %{buildroot} ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +

%files -f $work/$name.files
EOF
  } >"$work/$name.spec"
  build_spec "$work/$name.spec"
}

build_prefix pos "POS, installed in /pos" "POS build $id: the stages ${pos_stages[*]}, installed in /pos.
Nothing outside /pos; pos-fedora makes it the base of a Fedora system." "${pos_stages[@]}"
if ((${#sdk_stages[@]})); then
  build_prefix pos-sdk "The POS SDK, installed in /pos" "POS build $id: the compiler, binutils, kernel headers and developer
tools of the sdk stage, installed in /pos next to pos." "${sdk_stages[@]}"
fi

# --- pos-debuginfo -----------------------------------------------------

debug_stages=()
for s in "${stages[@]}"; do
  d=$bdir/assemble-debug/$s/pos/lib/debug
  [[ -d $d ]] && debug_stages+=("$s")
done
if ((${#debug_stages[@]})); then
  # Only what is under /pos/lib/debug is owned; the directories above it
  # belong to pos.
  for s in "${debug_stages[@]}"; do
    (cd "$bdir/assemble-debug/$s" && find pos/lib/debug -printf '%y /%p\n')
  done | sort -u -k2,2 >"$work/debug.paths"
  {
    echo '%defattr(-,root,root,-)'
    awk '$1 == "d" {print $2}' "$work/debug.paths" | rpm_escape | sed 's|^|%dir |'
    awk '$1 != "d" {print $2}' "$work/debug.paths" | rpm_escape
  } >"$work/pos-debuginfo.files"
  {
    spec_head pos-debuginfo "Debug info for POS"
    echo "Requires: pos = $evr"
    cat <<EOF

%description
The debug info split off the programs and libraries of pos and pos-sdk,
build $id, in /pos/lib/debug/.build-id, where gdb and debuginfod find it
by build ID.

%install
mkdir -p %{buildroot}/pos
$(for s in "${debug_stages[@]}"; do echo "cp -a '$bdir/assemble-debug/$s/pos/.' %{buildroot}/pos/"; done)
find %{buildroot} ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +

%files -f $work/pos-debuginfo.files
EOF
  } >"$work/pos-debuginfo.spec"
  build_spec "$work/pos-debuginfo.spec"
fi

# --- pos-fedora --------------------------------------------------------

# The Fedora packages POS replaces, for the POS packages in the stages.
claimed=()
while read -r p names; do
  p=${p%%#*}
  [[ -n $p && -n ${in_build[$p]:-} ]] || continue
  read -ra n <<<"${names%%#*}"
  claimed+=("${n[@]}")
done <"$base/rpm/fedora"
((${#claimed[@]})) || die "rpm/fedora lists nothing for ${stages[*]}"
printf '%s\n' "${claimed[@]}" | sort -u >"$work/claimed"

# What they provide, from Fedora's repositories, and every path in Fedora
# with the package that owns it.
dnf_query() {
  dnf repoquery -q --latest-limit=1 --arch=x86_64,noarch "$@"
}
dnf_query --qf '@%{name} %{evr}\n%{provides}\n' "${claimed[@]}" >"$work/fedora.provides"
for n in "${claimed[@]}"; do
  grep -q "^@$n " "$work/fedora.provides" || die "rpm/fedora: no package $n in Fedora $fedora"
done

# The sonames and symbol versions of the POS shared libraries, from rpm's
# own generator, as Fedora's packages get theirs.
for s in "${stages[@]}"; do
  find "$bdir/assemble/$s/pos" -type f -name '*.so*' -exec sh -c '
    for f; do [ "$(head -c 4 "$f")" = "$(printf "\177ELF")" ] && echo "$f"; done' sh {} +
done | /usr/lib/rpm/elfdeps --provides | sort -u >"$work/pos.sonames"

# A claim stands only if POS has every versioned soname and symbol version
# the Fedora package provides; a Fedora binary linked against it would
# not load otherwise. Unversioned plugin names and *_PRIVATE versions are
# internal to the Fedora package and not checked.
awk '/^@/ {n = $1; sub(/^@/, "", n); next}
     $1 !~ /^\// && $1 ~ /\.so\.[0-9]/ && $1 !~ /PRIVATE/ {print n, $1}' "$work/fedora.provides" |
  sort -u | awk 'NR == FNR {have[$1] = 1; next} !have[$2]' "$work/pos.sonames" - >"$work/unmet"
if [[ -s $work/unmet ]]; then
  awk '{c[$1]++; if (!s[$1]) s[$1] = $2} END {for (n in c) print n, c[n], s[n]}' "$work/unmet" | sort |
    while read -r n c s; do
      echo "pos-fedora: not replacing $n: POS lacks $c of its sonames and symbol versions ($s ...)" >&2
    done
  awk '{print $1}' "$work/unmet" | sort -u | comm -23 "$work/claimed" - >"$work/claimed.ok"
  mv "$work/claimed.ok" "$work/claimed"
fi
dnf_query --setopt=optional_metadata_types=filelists --qf '@%{name}\n%{files}\n' >"$work/fedora.files"

# Paths only Fedora packages pos-fedora does not replace have. pos-fedora
# does not link those, so such a package installs next to it without a
# file conflict. A path a replaced package also has is linked: the
# alternatives that have it too (coreutils-single for coreutils) provide
# the replaced name, so pos-fedora conflicts with them anyway.
awk 'NR == FNR {c[$1] = 1; next}
     /^@/ {claimed = c[substr($0, 2)]; next}
     NF {print (claimed ? "c" : "u"), $0}' "$work/claimed" "$work/fedora.files" |
  awk '{p = substr($0, 3)} $1 == "c" {c[p] = 1; next} {u[p] = 1}
       END {for (p in u) if (!c[p]) print p}' | sort -u >"$work/fedora.taken"

# The links: programs into /usr/bin (Fedora's /usr/sbin is a link to it),
# libraries and the loader into /usr/lib64 (/lib64 is a link to it). The
# loader link is what makes Fedora's binaries, which request
# /lib64/ld-linux-x86-64.so.2, run on POS glibc.
awk '$1 != "d" {print $2}' "$work/paths" | awk -F/ '
  ($3 == "bin" || $3 == "sbin") && NF == 4 {print "/usr/bin/" $4, "../../pos/" $3 "/" $4}
  $3 == "lib" && NF == 4 && ($4 ~ /\.so\./ || $4 ~ /^ld-linux/) {print "/usr/lib64/" $4, "../../pos/lib/" $4}
' | sort -u -k1,1 | join -v1 - "$work/fedora.taken" >"$work/links"

# Provides:
# - the claimed packages' own provides (names, name(x86-64), config(),
#   rtld(GNU_HASH), user() and group(), ...) at Fedora's versions, so
#   versioned requirements match. Not their sonames and paths, which
#   describe Fedora's files, and not bundled().
# - the sonames and symbol versions of the POS libraries: a Fedora binary
#   that needs a symbol version POS glibc does not have is not satisfied.
# - the linked paths under the names Fedora's merged directories give them.
{
  awk 'NR == FNR {c[$1] = 1; next}
       /^@/ {n = $1; sub(/^@/, "", n); next}
       c[n] && NF && $1 !~ /^\// && $1 !~ /\.so[.(]/ && $1 !~ /^bundled\(/' \
    "$work/claimed" "$work/fedora.provides"
  cat "$work/pos.sonames"
  awk '$1 ~ /^\/usr\/bin\// {n = substr($1, 10); print "/bin/" n; print "/usr/sbin/" n; print "/sbin/" n}' "$work/links"
  awk '$1 ~ /^\/usr\/lib64\// {print "/lib64/" substr($1, 12)}' "$work/links"
} | sort -u >"$work/pos-fedora.provides"

# The system's os-release is POS's (pos-integration), in place of Fedora's
# fedora-release, which rpm/fedora claims. fedora-release required Fedora's
# repositories (fedora-repos); pos-fedora does in its place. dnf's release
# version is the version of the system-release provider (fedora-release's
# is 44, pos-fedora's the build ID) unless a system-release(releasever)
# provide gives it.
osrel_install= osrel_files= osrel_tags=
if [[ -n ${in_build[pos-integration]:-} ]]; then
  osrel_install='ln -s ../../pos/lib/os-release %{buildroot}/usr/lib/os-release
ln -s ../usr/lib/os-release %{buildroot}/etc/os-release'
  osrel_files='/usr/lib/os-release
/etc/os-release'
  osrel_tags="Requires: fedora-repos
Provides: system-release(releasever) = $fedora"
fi

{
  spec_head pos-fedora "POS as the base of a Fedora system"
  echo "Requires: pos = $evr"
  # The base of the systems this is for (POS's own tools) includes the sdk;
  # its programs are linked and its sonames provided like the rest.
  ((${#sdk_stages[@]})) && echo "Requires: pos-sdk = $evr"
  echo "Requires: filesystem"
  [[ -z $osrel_tags ]] || echo "$osrel_tags"
  sed 's/^/Provides: /' "$work/pos-fedora.provides"
  sed 's/^/Conflicts: /' "$work/claimed"
  cat <<EOF

%description
POS build $id in place of the Fedora $fedora packages it replaces:
$(xargs <"$work/claimed" | fold -s -w 72)

It provides what those provide, links their programs and libraries in
/usr to /pos, and conflicts with them. Fedora packages that need them use
POS; dnf installs only what POS does not have. The POS loader also
searches /usr/lib64, after /pos/lib (/etc/pos/ld.so.conf, also as
/etc/ld.so.conf for tools that read the library path there), where Fedora
packages installed next to POS put their libraries. Fedora's dracut is
given POS's systemd, udev and dbus directories. The system's os-release
is POS's.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/lib %{buildroot}/usr/lib64 %{buildroot}/etc/pos
while read -r path target; do
  ln -s "\$target" "%{buildroot}\$path"
done <'$work/links'
printf '%s\n' /pos/lib /usr/lib64 >%{buildroot}/etc/pos/ld.so.conf
chmod 0644 %{buildroot}/etc/pos/ld.so.conf
ln -s pos/ld.so.conf %{buildroot}/etc/ld.so.conf
install -D -m 0644 '$base/rpm/dracut.conf' %{buildroot}/usr/lib/dracut/dracut.conf.d/50-pos.conf
$osrel_install

# The POS loader finds what is not in /pos/lib through its cache only, so
# the cache is updated after every package that adds libraries, before
# the scriptlets of later packages run their programs. Lua, as Fedora's
# glibc does: -p with a program would pass it the package count.
%post -p <lua>
rpm.execute("/pos/sbin/ldconfig")

%filetriggerin -p <lua> -- /usr/lib64 /pos/lib
rpm.execute("/pos/sbin/ldconfig")

%filetriggerpostun -p <lua> -- /usr/lib64 /pos/lib
rpm.execute("/pos/sbin/ldconfig")

%files
%dir /etc/pos
%config(noreplace) /etc/pos/ld.so.conf
/etc/ld.so.conf
/usr/lib/dracut/dracut.conf.d/50-pos.conf
$osrel_files
$(awk '{print $1}' "$work/links" | rpm_escape)
EOF
} >"$work/pos-fedora.spec"
build_spec "$work/pos-fedora.spec"

cp "$work/links" "$out/pos-fedora.links"
cp "$work/pos-fedora.provides" "$out/pos-fedora.provides"
cp "$work/unmet" "$out/pos-fedora.unmet"
rm -rf "$work"
echo "$out"
