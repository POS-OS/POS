# Sourced by pkg_setup for builds that require pos-link.
#
# The sdk compiler already searches /pos/include and /pos/lib. /pos/include
# must not be named again: that moves it in front of the libstdc++
# directories, gcc drops the later duplicate, and libstdc++'s
# #include_next <stdlib.h> then finds nothing after itself.
#
# No -rpath: the POS loader finds /pos/lib by itself. Its cache is
# /etc/pos/ld.so.cache, not the build container's /etc/ld.so.cache (BUILD.md
# "Core libs stage").
export LDFLAGS="-L/pos/lib -Wl,--dynamic-linker=/pos/lib/ld-linux-x86-64.so.2${LDFLAGS:+ $LDFLAGS}"
# Replace the host search path so .pc files cannot fall back to /usr.
export PKG_CONFIG_LIBDIR=/pos/lib/pkgconfig
unset PKG_CONFIG_PATH
