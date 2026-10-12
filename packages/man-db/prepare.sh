#!/usr/bin/env bash
# The build system is generated (autogen.sh or bootstrap).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_gen
prep_finish
