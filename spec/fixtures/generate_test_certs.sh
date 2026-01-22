#!/bin/bash

# Generate test SSL certificates for integration tests
# This script creates self-signed certificates for testing server-to-server SSL connections

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_DIR="$SCRIPT_DIR/ssl"

echo "Generating SSL certificates for testing in $SSL_DIR..."

# Create SSL directories
mkdir -p "$SSL_DIR/ca"
mkdir -p "$SSL_DIR/server1"
mkdir -p "$SSL_DIR/server2"

cd "$SSL_DIR"

# Generate CA key and certificate
openssl genrsa -out ca/ca.key 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key ca/ca.key -out ca/ca.crt \
  -subj "/C=US/ST=Test/L=Test/O=TestCA/CN=Test Certificate Authority" 2>/dev/null

# Generate Server 1 certificate
openssl genrsa -out server1/server.key 2048 2>/dev/null
openssl req -new -key server1/server.key -out server1/server.csr \
  -subj "/C=US/ST=Test/L=Test/O=Test/CN=server1.test.local" 2>/dev/null
openssl x509 -req -days 3650 -in server1/server.csr \
  -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
  -out server1/server.crt 2>/dev/null
rm server1/server.csr

# Generate Server 2 certificate
openssl genrsa -out server2/server.key 2048 2>/dev/null
openssl req -new -key server2/server.key -out server2/server.csr \
  -subj "/C=US/ST=Test/L=Test/O=Test/CN=server2.test.local" 2>/dev/null
openssl x509 -req -days 3650 -in server2/server.csr \
  -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
  -out server2/server.crt 2>/dev/null
rm server2/server.csr

echo "Test SSL certificates generated successfully!"
echo "  CA cert: $SSL_DIR/ca/ca.crt"
echo "  Server 1: $SSL_DIR/server1/server.crt"
echo "  Server 2: $SSL_DIR/server2/server.crt"