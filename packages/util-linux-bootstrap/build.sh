#!/usr/bin/env bash
# util-linux without libsystemd: systemd links libmount and libblkid,
# and util-linux links libsystemd.

set -euo pipefail

configure_extra=(--without-systemd)
source "$POS_BASE/packages/util-linux/build.sh"
