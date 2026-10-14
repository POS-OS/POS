# Sourced by pkg_setup for builds where gcc is installed.
#
# It searches /pos only. glibc and gcc's target libraries use it too: glibc
# overrides the part of its search that would be circular (it passes
# -nostdinc and -nostdlib); the target libraries are built by the new
# xgcc, not by this CC.
export CC=/pos/bin/gcc
export CXX=/pos/bin/g++
export LD=/pos/bin/ld
