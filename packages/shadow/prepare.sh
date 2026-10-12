#!/usr/bin/env bash
# Not autogen.sh: it runs configure itself with developer defaults
# (-Werror, --with-selinux, --without-libpam, libbsd on).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
# chsh.c includes libeconf.h whenever vendordir is enabled. libeconf is not
# in POS; getdef.c only uses it under USE_ECONF, which stays off. chsh is
# not installed (util-linux provides it).
sed -i 's/#ifdef HAVE_VENDORDIR/#ifdef USE_ECONF/' src/chsh.c
autoreconf -fi
prep_finish
