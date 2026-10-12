#!/usr/bin/env bash
# The git tree has no configure or help text; Makefile.aut generates
# them (autoconf, and nroff for the help text).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
make -f Makefile.aut distfiles
prep_finish
