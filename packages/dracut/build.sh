#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# dracut-install finds the libraries a program needs as glibc's loader
# usually would: /etc/ld.so.conf, then /lib64, /usr/lib64, ... POS's loader
# reads /etc/pos/ld.so.conf and searches /pos/lib by default (packages/glibc),
# so it is told the same, ahead of the usual directories, which libraries
# installed next to POS are in.
c=src/install/dracut-install.c
grep -qF 'search_via_ldconf("/etc/ld.so.conf", soname, match64, match32) ?:' "$c" || {
  echo "dracut: $c: no ld.so.conf search to change" >&2
  exit 1
}
sed -i 's|search_via_ldconf("/etc/ld.so.conf", soname, match64, match32) ?:|search_via_ldconf("/etc/pos/ld.so.conf", soname, match64, match32) ?:\n               search_libdir("/pos/lib", soname, match64, match32) ?:|' "$c"
# Its ldconfig step copies the loader's configuration into the initramfs
# and makes the cache from it: POS's, which puts the cache in /etc/pos.
grep -qF '"${dracutsysrootdir-}"/etc/ld.so.conf "${dracutsysrootdir-}"/etc/ld.so.conf.d/*; do' dracut.sh &&
  grep -qF -- '-r "$dstdir" -f /etc/ld.so.conf;' dracut.sh || {
  echo "dracut: dracut.sh: no ldconfig step to change" >&2
  exit 1
}
sed -i -e 's|"${dracutsysrootdir-}"/etc/ld.so.conf "${dracutsysrootdir-}"/etc/ld.so.conf.d/\*; do|"${dracutsysrootdir-}"/etc/pos/ld.so.conf; do|' \
  -e 's|-r "$dstdir" -f /etc/ld.so.conf;|-r "$dstdir" -f /etc/pos/ld.so.conf;|' dracut.sh
# dracut makes the initramfs, when an image is made and on a running
# system (kernel-install's dracut plugin). It is in /pos/lib/dracut, its
# configuration in /etc/dracut.conf{,.d}. Not the Rust dracut-cpio; GNU
# cpio makes the archive. No documentation: it needs asciidoctor.
./configure --prefix="$prefix" \
            --libdir="${prefix}/lib" \
            --sysconfdir="$sysconfdir" \
            --systemdsystemunitdir="${prefix}/lib/systemd/system" \
            --bashcompletiondir="${prefix}/share/bash-completion/completions" \
            --disable-dracut-cpio \
            --disable-documentation
make -j"$nproc"
make DESTDIR="$dest_dir" install
# dracut takes its directory to be <bin>/../lib/dracut, from the path it
# is run by, without following links: run as /usr/bin/dracut (pos-fedora's
# link, which kernel-install's plugin finds) it looks in /usr/lib/dracut.
f=${dest_dir}${prefix}/bin/dracut
awk -v dir="${prefix}/lib/dracut" '
  index($0, "[[ ${dracutbasedir-} ]] || dracutbasedir=") == 1 {
    $0 = "[[ ${dracutbasedir-} ]] || dracutbasedir=" dir; set = 1
  }
  {print}
  END {exit !set}' "$f" >"$f.tmp" || {
  echo "dracut: no default dracutbasedir to set" >&2
  exit 1
}
cat "$f.tmp" >"$f"
rm "$f.tmp"
# Where POS's systemd, udev and dbus have their files, which dracut would
# otherwise take to be Fedora's /usr (01-dist.conf).
install -m 0644 "$base/packages/dracut/01-dist.conf" \
  "${dest_dir}${prefix}/lib/dracut/dracut.conf.d/01-dist.conf"

pkg_finish
