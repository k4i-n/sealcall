#!/bin/bash
# Creates the self-signed code signing identity that sealcall builds are signed with.
# The private key goes from openssl to the login keychain through pipes only, never to disk.
set -euo pipefail
name=${1:?usage: signing-identity.sh "<certificate name>"}
here=$(cd "$(dirname "$0")" && pwd)

if security find-certificate -c "$name" >/dev/null 2>&1; then
  echo "a certificate named \"$name\" already exists in your keychains" >&2
  exit 1
fi

config=$(mktemp)
trap 'rm -f "$config"' EXIT
cat > "$config" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

SEALCALL_P12_PASS=$(/usr/bin/openssl rand -hex 32)
export SEALCALL_P12_PASS
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -config "$config" -keyout /dev/stdout 2>/dev/null \
  | /usr/bin/openssl pkcs12 -export -passout env:SEALCALL_P12_PASS \
  | swift "$here/import-identity.swift"
security find-identity -p codesigning | grep "\"$name\""
