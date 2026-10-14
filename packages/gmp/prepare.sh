#!/usr/bin/env bash
# autoreconf generates the build system. doc/version.texi, which release
# tarballs ship, is written here: gmp is not in maintainer mode, so its
# Makefile has no rule to make it, and the info manual includes it. Dated
# with the upstream commit, where the release process uses the manual's
# file date.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_gen
version=$(sed -n "s/^PACKAGE_VERSION='\(.*\)'$/\1/p" configure)
read -r day month year < <(date -u -d "$(prep_upstream date)" '+%-d %B %Y')
cat > doc/version.texi <<EOF2
@set UPDATED $day $month $year
@set UPDATED-MONTH $month $year
@set EDITION $version
@set VERSION $version
EOF2
prep_finish
