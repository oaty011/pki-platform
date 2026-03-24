#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-.local/test-ca}"
ECU_DEVICE_ID="${ECU_DEVICE_ID:-deviceid}"
ECU_OU="${ECU_OU:-TBOX}"
APP_SUBJECT_ID="${APP_SUBJECT_ID:-installid}"
P12_PASSWORD="${P12_PASSWORD:-changeit}"

ROOT_SUBJECT="/CN=DFMC Root CA TEST/O=DFMC_CA/C=CN"
SUB_SUBJECT="/CN=DFMC Sub CA TEST/O=DFMC_CA/C=CN"
ECU_SUBJECT="/CN=${ECU_DEVICE_ID}/OU=${ECU_OU}/O=DFMC ECU/C=CN"
APP_SUBJECT="/CN=${APP_SUBJECT_ID}/OU=Vehicle Controller SDK/O=DFMC/C=CN"

mkdir -p "${OUT_DIR}"

ROOT_EXT="${OUT_DIR}/root-ca.ext"
SUB_EXT="${OUT_DIR}/sub-ca.ext"
LEAF_EXT="${OUT_DIR}/leaf.ext"

cat > "${ROOT_EXT}" <<'EOF'
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
EOF

cat > "${SUB_EXT}" <<'EOF'
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

cat > "${LEAF_EXT}" <<'EOF'
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

echo "== Generate Root CA =="
openssl genrsa -out "${OUT_DIR}/root-ca.key.pem" 4096
openssl req -x509 -new -sha256 -days 3650 \
  -key "${OUT_DIR}/root-ca.key.pem" \
  -subj "${ROOT_SUBJECT}" \
  -out "${OUT_DIR}/root-ca.cert.pem" \
  -extensions v3_ca \
  -config <(
    cat /etc/ssl/openssl.cnf
    printf '\n[v3_ca]\n'
    cat "${ROOT_EXT}"
  )

echo "== Generate Intermediate CA =="
openssl genrsa -out "${OUT_DIR}/sub-ca.key.pem" 4096
openssl req -new -sha256 \
  -key "${OUT_DIR}/sub-ca.key.pem" \
  -subj "${SUB_SUBJECT}" \
  -out "${OUT_DIR}/sub-ca.csr.pem"
openssl x509 -req -sha256 -days 1825 \
  -in "${OUT_DIR}/sub-ca.csr.pem" \
  -CA "${OUT_DIR}/root-ca.cert.pem" \
  -CAkey "${OUT_DIR}/root-ca.key.pem" \
  -CAcreateserial \
  -out "${OUT_DIR}/sub-ca.cert.pem" \
  -extfile "${SUB_EXT}"
cat "${OUT_DIR}/sub-ca.cert.pem" "${OUT_DIR}/root-ca.cert.pem" > "${OUT_DIR}/sub-ca.chain.pem"

echo "== Generate ECU leaf =="
openssl genrsa -out "${OUT_DIR}/ecu-leaf.key.pem" 2048
openssl req -new -sha256 \
  -key "${OUT_DIR}/ecu-leaf.key.pem" \
  -subj "${ECU_SUBJECT}" \
  -out "${OUT_DIR}/ecu-leaf.csr.pem"
openssl x509 -req -sha256 -days 365 \
  -in "${OUT_DIR}/ecu-leaf.csr.pem" \
  -CA "${OUT_DIR}/sub-ca.cert.pem" \
  -CAkey "${OUT_DIR}/sub-ca.key.pem" \
  -CAcreateserial \
  -out "${OUT_DIR}/ecu-leaf.cert.pem" \
  -extfile "${LEAF_EXT}"
cat "${OUT_DIR}/ecu-leaf.cert.pem" "${OUT_DIR}/sub-ca.cert.pem" "${OUT_DIR}/root-ca.cert.pem" > "${OUT_DIR}/ecu-leaf.fullchain.pem"

echo "== Generate APP leaf =="
openssl genrsa -out "${OUT_DIR}/app-leaf.key.pem" 2048
openssl req -new -sha256 \
  -key "${OUT_DIR}/app-leaf.key.pem" \
  -subj "${APP_SUBJECT}" \
  -out "${OUT_DIR}/app-leaf.csr.pem"
openssl x509 -req -sha256 -days 365 \
  -in "${OUT_DIR}/app-leaf.csr.pem" \
  -CA "${OUT_DIR}/sub-ca.cert.pem" \
  -CAkey "${OUT_DIR}/sub-ca.key.pem" \
  -CAcreateserial \
  -out "${OUT_DIR}/app-leaf.cert.pem" \
  -extfile "${LEAF_EXT}"
cat "${OUT_DIR}/app-leaf.cert.pem" "${OUT_DIR}/sub-ca.cert.pem" "${OUT_DIR}/root-ca.cert.pem" > "${OUT_DIR}/app-leaf.fullchain.pem"

echo "== Export PKCS12 for soft signer =="
openssl pkcs12 -export \
  -inkey "${OUT_DIR}/sub-ca.key.pem" \
  -in "${OUT_DIR}/sub-ca.cert.pem" \
  -certfile "${OUT_DIR}/root-ca.cert.pem" \
  -name "softsigner-sub-ca" \
  -out "${OUT_DIR}/sub-ca.p12" \
  -passout "pass:${P12_PASSWORD}"

echo
echo "Generated files:"
find "${OUT_DIR}" -maxdepth 1 -type f | sort

echo
echo "Verify intermediate signed by root:"
echo "openssl verify -CAfile ${OUT_DIR}/root-ca.cert.pem ${OUT_DIR}/sub-ca.cert.pem"

echo "Verify ECU leaf signed by intermediate/root chain:"
echo "openssl verify -CAfile ${OUT_DIR}/root-ca.cert.pem -untrusted ${OUT_DIR}/sub-ca.cert.pem ${OUT_DIR}/ecu-leaf.cert.pem"

echo "Verify APP leaf signed by intermediate/root chain:"
echo "openssl verify -CAfile ${OUT_DIR}/root-ca.cert.pem -untrusted ${OUT_DIR}/sub-ca.cert.pem ${OUT_DIR}/app-leaf.cert.pem"

echo
echo "Example soft signer settings:"
echo "PKCS12:"
echo "  PKI_ISSUANCE_SIGNER_SOFT_KEYSTORE_PATH=${OUT_DIR}/sub-ca.p12"
echo "  PKI_ISSUANCE_SIGNER_SOFT_KEYSTORE_PASSWORD=${P12_PASSWORD}"
echo "  PKI_ISSUANCE_SIGNER_SOFT_KEY_ALIAS=softsigner-sub-ca"
echo "  PKI_ISSUANCE_SIGNER_SOFT_KEY_PASSWORD=${P12_PASSWORD}"

echo "PEM:"
echo "  PKI_ISSUANCE_SIGNER_SOFT_CERTIFICATE_PATH=${OUT_DIR}/sub-ca.cert.pem"
echo "  PKI_ISSUANCE_SIGNER_SOFT_PRIVATE_KEY_PATH=${OUT_DIR}/sub-ca.key.pem"
echo "  PKI_ISSUANCE_SIGNER_SOFT_SIGNATURE_ALGORITHM=SHA256withRSA"
