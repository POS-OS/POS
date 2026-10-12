#!/usr/bin/env bash
# gawk carries its own gnulib subset and generated files; bootstrap.sh
# only fixes timestamps so configure is not regenerated. The build copies
# the prepared tree with its timestamps.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
./bootstrap.sh
prep_finish
