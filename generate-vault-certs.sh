#!/bin/bash

# Generate CA private key
openssl genrsa -out ca-key.pem 2048

# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca.pem \
  -subj "/CN=Vault CA"

# Generate Vault private key
openssl genrsa -out vault-key.pem 2048

# Create certificate signing request
openssl req -new -key vault-key.pem -out vault.csr \
  -subj "/CN=vault.local"

# Create config for SAN
cat > vault-san.cnf << 'SAN'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = vault.local
DNS.2 = vault
DNS.3 = localhost
IP.1 = 10.0.0.212
IP.2 = 127.0.0.1
SAN

# Sign the certificate
openssl x509 -req -in vault.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out vault.pem -days 3650 \
  -extensions v3_req -extfile vault-san.cnf

# Cleanup
rm vault.csr vault-san.cnf ca.srl

echo "Generated: ca.pem, vault.pem, vault-key.pem"
ls -lh *.pem
