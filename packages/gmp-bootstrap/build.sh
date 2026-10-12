#!/usr/bin/env bash
# gmp for the sdk compiler. libgmpxx is left out: gcc does not need it,
# and the libstdc++ it would link is the bootstrap one.

set -euo pipefail

configure_extra=(--disable-cxx)
source "$POS_BASE/packages/gmp/build.sh"
