#!/usr/bin/env bash
# libexpat keeps the library in the expat/ subdirectory; autoreconf
# generates its build system there.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
(cd expat && prep_gen)
prep_finish
