#!/usr/bin/env bash
# gnulib bootstrap: translations are fetched, then the build system is
# generated against src/gnulib.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_version
prep_pull
prep_gen
prep_finish
