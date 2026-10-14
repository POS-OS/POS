#!/usr/bin/env python3
"""
parse-certdata.py: Extracts trusted root CA certificates from Mozilla NSS certdata.txt.

This script parses PKCS#11 object definitions in Mozilla's certdata.txt, filters for
certificates explicitly trusted for SSL/TLS server authentication
(CKA_TRUST_SERVER_AUTH == CKT_NSS_TRUSTED_DELEGATOR), and converts the raw DER
octal data into standard PEM format without requiring external cryptographic libraries.

Outputs:
  - <out_dir>/certs/<sanitized_name>.crt (individual PEM certificates)
  - <out_dir>/ca-bundle.crt (unified PEM certificate bundle)
"""

import base64
import os
import re
import sys
import textwrap


def parse_certdata(certdata_path):
    """Parses certdata.txt into a list of PKCS#11 object dictionaries."""
    objects = []
    in_data = False
    in_multiline = False
    field = None
    ftype = None
    val = None
    obj = {}

    with open(certdata_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()

            # Ignore header comments before BEGINDATA, but start if BEGINDATA or CKA_CLASS seen
            if not in_data:
                if line.startswith("BEGINDATA") or line.startswith("CKA_CLASS"):
                    in_data = True
                else:
                    continue

            # Skip comments
            if line.startswith("#"):
                continue

            # Empty lines demarcate objects (when not in a multiline block)
            if not line:
                if obj and not in_multiline:
                    objects.append(obj)
                    obj = {}
                continue

            # Handle multiline octal data
            if in_multiline:
                if line == "END":
                    obj[field] = bytes(val)
                    in_multiline = False
                else:
                    for m in re.finditer(r"\\([0-7]{1,3})", line):
                        val.append(int(m.group(1), 8))
                continue

            # Start of a new object
            if line.startswith("CKA_CLASS"):
                if obj:
                    objects.append(obj)
                    obj = {}

            parts = line.split(" ", 2)
            field = parts[0]
            ftype = parts[1] if len(parts) > 1 else ""
            fval = parts[2] if len(parts) > 2 else ""

            if ftype == "MULTILINE_OCTAL":
                in_multiline = True
                val = bytearray()
            else:
                obj[field] = fval

    if obj:
        objects.append(obj)

    return objects


def sanitize_filename(label):
    """Sanitizes a certificate label into a safe filesystem filename."""
    clean = label.strip('"').strip("'")
    clean = re.sub(r"[^A-Za-z0-9._+-]", "_", clean)
    clean = re.sub(r"_+", "_", clean).strip("_")
    return clean or "certificate"


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(f"Usage: {sys.argv[0]} <path/to/certdata.txt> <output_directory>\n")
        sys.exit(1)

    certdata_path = sys.argv[1]
    out_dir = sys.argv[2]
    certs_dir = os.path.join(out_dir, "certs")
    bundle_path = os.path.join(out_dir, "ca-bundle.crt")

    if not os.path.isfile(certdata_path):
        sys.stderr.write(f"Error: certdata file not found: {certdata_path}\n")
        sys.exit(1)

    os.makedirs(certs_dir, exist_ok=True)

    objects = parse_certdata(certdata_path)

    # 1. Extract trust attributes
    trusted_labels = set()
    untrusted_count = 0

    for obj in objects:
        if obj.get("CKA_CLASS") == "CKO_NSS_TRUST":
            label = obj.get("CKA_LABEL", "").strip('"')
            server_auth = obj.get("CKA_TRUST_SERVER_AUTH")
            if server_auth == "CKT_NSS_TRUSTED_DELEGATOR":
                trusted_labels.add(label)
            elif server_auth in ("CKT_NSS_NOT_TRUSTED", "CKT_NSS_MUST_VERIFY_TRUST"):
                untrusted_count += 1

    # 2. Extract matching certificates and emit PEMs
    seen_filenames = set()
    extracted_certs = []

    for obj in objects:
        if obj.get("CKA_CLASS") == "CKO_CERTIFICATE":
            label = obj.get("CKA_LABEL", "").strip('"')
            if label not in trusted_labels:
                continue

            raw_der = obj.get("CKA_VALUE")
            if not raw_der:
                continue

            b64_data = base64.b64encode(raw_der).decode("ascii")
            pem_wrapped = "\n".join(textwrap.wrap(b64_data, 64))
            pem_cert = (
                f"-----BEGIN CERTIFICATE-----\n"
                f"{pem_wrapped}\n"
                f"-----END CERTIFICATE-----\n"
            )

            base_fname = sanitize_filename(label)
            fname = f"{base_fname}.crt"
            counter = 2
            while fname in seen_filenames:
                fname = f"{base_fname}_{counter}.crt"
                counter += 1
            seen_filenames.add(fname)

            with open(os.path.join(certs_dir, fname), "w", encoding="utf-8") as f:
                f.write(pem_cert)

            extracted_certs.append((label, pem_cert))

    # 3. Write unified CA bundle
    with open(bundle_path, "w", encoding="utf-8") as f:
        f.write("# POS CA Trust Store Bundle\n")
        f.write("# Generated from Mozilla NSS certdata.txt\n")
        f.write(f"# Total certificates: {len(extracted_certs)}\n\n")
        for label, pem_cert in extracted_certs:
            f.write(f"# Certificate: {label}\n")
            f.write(pem_cert)
            f.write("\n")

    print(
        f"Processed certdata.txt: {len(extracted_certs)} trusted certificates extracted "
        f"({untrusted_count} untrusted/non-delegator records skipped)."
    )
    print(f"Individual certificates written to: {certs_dir}")
    print(f"Unified CA bundle written to: {bundle_path}")


if __name__ == "__main__":
    main()
