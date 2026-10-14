#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1

certdata=""
for p in "$src_dir/lib/ckfw/builtins/certdata.txt" \
         "$src_dir/security/nss/lib/ckfw/builtins/certdata.txt" \
         "$src_dir/certdata.txt"; do
  if [[ -f "$p" ]]; then
    certdata="$p"
    break
  fi
done

if [[ -z "$certdata" ]]; then
  echo "Error: certdata.txt not found in $src_dir" >&2
  exit 1
fi

python3 "$base/packages/$package/parse-certdata.py" "$certdata" "$build_dir/out"

# Install individual certificates
mkdir -p "${dest_dir}${prefix}/share/ca-certificates/mozilla"
install -m 0644 "$build_dir/out/certs/"*.crt "${dest_dir}${prefix}/share/ca-certificates/mozilla/"

# Install unified CA bundle
install -D -m 0644 "$build_dir/out/ca-bundle.crt" "${dest_dir}${prefix}/share/ca-certificates/ca-bundle.crt"

# System-wide OpenSSL and standard Linux compatibility in /etc/ssl:
# OpenSSL default search file is /etc/ssl/cert.pem when OPENSSLDIR is /etc/ssl.
# Standard path for Debian/Ubuntu/Python/Go is /etc/ssl/certs/ca-certificates.crt.
# pkg_factory will move these into /pos/share/factory/etc and generate factory
# tmpfiles C lines so systemd-tmpfiles seeds them into /etc at boot and image creation.
mkdir -p "${dest_dir}/etc/ssl/certs"
ln -sf ../../pos/share/ca-certificates/ca-bundle.crt "${dest_dir}/etc/ssl/cert.pem"
ln -sf ../cert.pem "${dest_dir}/etc/ssl/certs/ca-certificates.crt"

pkg_finish
