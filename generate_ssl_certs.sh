#!/bin/bash

# Generate SSL certificates for testing crIRCd SSL support
# This creates self-signed certificates suitable for testing server-to-server SSL links

SSL_DIR="ssl"
DAYS_VALID=365
COUNTRY="US"
STATE="TestState"
CITY="TestCity"
ORG="TestIRC Network"

echo "========================================"
echo "IRC SSL Certificate Generator"
echo "========================================"

# Create SSL directory structure
echo "Creating SSL directory structure..."
mkdir -p $SSL_DIR/server1
mkdir -p $SSL_DIR/server2
mkdir -p $SSL_DIR/ca

# Generate a CA for testing (optional, for certificate verification tests)
echo ""
echo "Generating Certificate Authority (CA)..."
openssl genrsa -out $SSL_DIR/ca/ca.key 4096 2>/dev/null
openssl req -new -x509 -days 3650 -key $SSL_DIR/ca/ca.key -out $SSL_DIR/ca/ca.crt \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/CN=TestIRC CA" 2>/dev/null
echo "✓ CA certificate created"

# Function to generate server certificate
generate_server_cert() {
    local server_num=$1
    local server_name=$2
    local server_dir="$SSL_DIR/server$server_num"

    echo ""
    echo "Generating certificates for Server $server_num ($server_name)..."

    # Generate private key
    openssl genrsa -out $server_dir/server.key 2048 2>/dev/null

    # Generate CSR with SAN for localhost
    cat > $server_dir/server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
CN = $server_name

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $server_name
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate CSR
    openssl req -new -key $server_dir/server.key -out $server_dir/server.csr \
        -config $server_dir/server.conf 2>/dev/null

    # Sign with CA
    openssl x509 -req -in $server_dir/server.csr \
        -CA $SSL_DIR/ca/ca.crt -CAkey $SSL_DIR/ca/ca.key \
        -CAcreateserial -out $server_dir/server.crt \
        -days $DAYS_VALID -extensions v3_req -extfile $server_dir/server.conf 2>/dev/null

    # Clean up
    rm -f $server_dir/server.csr $server_dir/server.conf

    # Set permissions
    chmod 600 $server_dir/server.key
    chmod 644 $server_dir/server.crt

    echo "✓ Server $server_num certificates created"
}

# Generate certificates for both test servers
generate_server_cert 1 "irc1.test.local"
generate_server_cert 2 "irc2.test.local"

echo ""
echo "========================================"
echo "SSL certificates generated successfully!"
echo "========================================"
echo ""
echo "Generated files:"
echo "  CA Certificate: $SSL_DIR/ca/ca.crt"
echo "  Server 1:"
echo "    Certificate: $SSL_DIR/server1/server.crt"
echo "    Private Key: $SSL_DIR/server1/server.key"
echo "  Server 2:"
echo "    Certificate: $SSL_DIR/server2/server.crt"
echo "    Private Key: $SSL_DIR/server2/server.key"
echo ""
echo "To use these certificates, update your config files:"
echo ""
echo "For Server 1 (config_server1_ssl.yml):"
echo "  ssl:"
echo "    enabled: true"
echo "    port: 6697"
echo "    cert_file: \"$SSL_DIR/server1/server.crt\""
echo "    key_file: \"$SSL_DIR/server1/server.key\""
echo "    ca_file: \"$SSL_DIR/ca/ca.crt\""
echo ""
echo "For Server 2 (config_server2_ssl.yml):"
echo "  ssl:"
echo "    enabled: true"
echo "    port: 7697"
echo "    cert_file: \"$SSL_DIR/server2/server.crt\""
echo "    key_file: \"$SSL_DIR/server2/server.key\""
echo "    ca_file: \"$SSL_DIR/ca/ca.crt\""
echo ""
echo "WARNING: These are self-signed certificates for testing only!"