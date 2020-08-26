#!/usr/bin/env bash

set -o pipefail -eux

SUBJECT="${1}"
PASSWORD="${2}"

generate () {
    KEY="${1}"
    ALGORITHM="${2:-}"
    EXTRA_OPTIONS=()

    if [ -z "${ALGORITHM}" ]; then
        OUTPUT_PATH="${KEY}"

    else
        echo "Generating RSASSA-PSS certificate"
        OUTPUT_PATH="${KEY}-${ALGORITHM}"
        EXTRA_OPTIONS=("-sigopt" "rsa_padding_mode:${ALGORITHM}")

    fi

    echo "Generating ${KEY} signed cert"
    openssl req \
        -new \
        "-${KEY}" \
        -subj "/CN=${SUBJECT}" \
        -newkey rsa:2048 \
        -keyout "${OUTPUT_PATH}.key" \
        -out "${OUTPUT_PATH}.csr" \
        -config openssl.conf \
        -reqexts req \
        -passin pass:"${PASSWORD}" \
        -passout pass:"${PASSWORD}" \
        ${EXTRA_OPTIONS[@]}

    openssl x509 \
        -req \
        -in "${OUTPUT_PATH}.csr" \
        -"-${KEY}" \
        -CA ca.pem \
        -CAkey ca.key \
        -CAcreateserial \
        -out "${OUTPUT_PATH}.pem" \
        -days 365 \
        -extfile openssl.conf \
        -extensions req \
        -passin pass:"${PASSWORD}" \
        ${EXTRA_OPTIONS[@]}

    openssl pkcs12 \
        -export \
        -out "${OUTPUT_PATH}.pfx" \
        -inkey "${OUTPUT_PATH}.key" \
        -in "${OUTPUT_PATH}.pem" \
        -passin pass:"${PASSWORD}" \
        -passout pass:"${PASSWORD}"
}

echo "Generating CA issuer"
openssl genrsa \
    -aes256 \
    -out ca.key \
    -passout pass:"${PASSWORD}"

openssl req \
    -new \
    -x509 \
    -days 365 \
    -key ca.key \
    -out ca.pem \
    -subj "/CN=OMI Root" \
    -passin pass:"${PASSWORD}"

generate sha1
generate sha224
generate sha256
generate sha256 pss
generate sha384
generate sha512
generate sha512 pss

touch complete.txt
