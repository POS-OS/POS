#!/usr/bin/env bash
# libzstd for the sdk compiler and binutils. The zstd program is not
# used here; zlib and xz support is left out so the tools image's
# libraries are not picked up.

set -euo pipefail

configure_extra=(HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0)
source "$POS_BASE/packages/zstd/build.sh"
