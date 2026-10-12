# Sourced by pkg_setup for builds that require pos-link-host.
#
# The Fedora compiler searches /usr. Put /pos ahead of it. -isystem, not -I:
# glibc headers must stay system headers so packages that build with
# -Werror do not fail on warnings inside them. C_INCLUDE_PATH is treated
# like -isystem; CPATH would act like -I. /usr stays in the search after
# /pos, so a library missing from /pos is still found in the tools image
# (BUILD.md "Core libs stage").
export CPPFLAGS="-isystem /pos/include${CPPFLAGS:+ $CPPFLAGS}"
export C_INCLUDE_PATH="/pos/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
export CPLUS_INCLUDE_PATH="/pos/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH="/pos/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"

# shellcheck source=../pos-link/env.sh
source "$POS_BASE/packages/pos-link/env.sh"
