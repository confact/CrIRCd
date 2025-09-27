#!/bin/bash

# Generate SSL certificates for testing crIRCd SSL support
# This creates self-signed certificates suitable for testing only

SSL_DIR="ssl"
DAYS_VALID=365
COUNTRY="US"
STATE="State"
CITY="City"
ORG="IRC Network"
CN="irc.example.com"

echo "Creating SSL directory..."
mkdir -p $SSL_DIR

echo "Generating private key..."
openssl genrsa -out $SSL_DIR/server.key 2048

echo "Generating certificate signing request..."
openssl req -new -key $SSL_DIR/server.key -out $SSL_DIR/server.csr \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/CN=$CN"

echo "Generating self-signed certificate..."
openssl x509 -req -days $DAYS_VALID -in $SSL_DIR/server.csr \
    -signkey $SSL_DIR/server.key -out $SSL_DIR/server.crt

echo "Cleaning up CSR..."
rm $SSL_DIR/server.csr

echo "Setting appropriate permissions..."
chmod 600 $SSL_DIR/server.key
chmod 644 $SSL_DIR/server.crt

echo ""
echo "SSL certificates generated successfully in $SSL_DIR/"
echo ""
echo "To use these certificates, update your config.yml with:"
echo "  ssl:"
echo "    enabled: true"
echo "    port: 6697"
echo "    cert_file: \"$SSL_DIR/server.crt\""
echo "    key_file: \"$SSL_DIR/server.key\""
echo ""
echo "WARNING: These are self-signed certificates for testing only!"
echo "For production, use certificates from a trusted Certificate Authority."