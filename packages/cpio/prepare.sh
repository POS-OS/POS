#!/usr/bin/env bash
# gnulib bootstrap, against src/gnulib. cpio's bootstrap (2015) has no
# separate pull and generate phases: one run fetches the translations and
# generates the build system, taking paxutils' files from the tree's
# paxutils (with-sources).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_version
./bootstrap --no-git --copy
prep_finish
