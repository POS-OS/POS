#!/usr/bin/env bash
# The default PAM configuration goes to pam's vendor directory
# (packages/pam: VENDORDIR=/pos/share/pam), not to /etc: it applies
# without being copied, and /etc/pam.d overrides it per service. os-release
# is the system's identity: /usr/lib/os-release links to it (image layout,
# pos-fedora). The presets are POS's, ahead of systemd's.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

install -d "$dest_dir$prefix/share/pam/pam.d"
install -m 0644 "$src_dir"/pam.d/* "$dest_dir$prefix/share/pam/pam.d/"
install -D -m 0644 "$src_dir/os-release" "$dest_dir$prefix/lib/os-release"
install -d "$dest_dir$prefix/lib/systemd/system-preset"
install -m 0644 "$src_dir"/presets/*.preset "$dest_dir$prefix/lib/systemd/system-preset/"

pkg_finish
