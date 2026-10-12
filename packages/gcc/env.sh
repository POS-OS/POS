# Sourced by pkg_setup for builds where gcc is installed. gcc-bootstrap
# installs to the same paths and sources this file.
#
# It searches /pos only. glibc and gcc-runtime use it too: each already
# overrides the part of its search that would be circular (glibc passes
# -nostdinc and -nostdlib; gcc-runtime's target libraries are built by its
# own xgcc, not by this CC).
export CC=/pos/bin/gcc
export CXX=/pos/bin/g++
export LD=/pos/bin/ld
