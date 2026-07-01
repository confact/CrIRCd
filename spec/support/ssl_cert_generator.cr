require "file_utils"

# SSL certificate generator for testing
class SSLCertificateGenerator
  def self.generate_test_certificates(base_dir : String)
    FileUtils.mkdir_p("#{base_dir}/ca")
    FileUtils.mkdir_p("#{base_dir}/server1")
    FileUtils.mkdir_p("#{base_dir}/server2")

    # Generate CA key and certificate using openssl commands
    generate_ca(base_dir)

    # Generate server certificates
    generate_server_cert(base_dir, "server1")
    generate_server_cert(base_dir, "server2")
  end

  private def self.generate_ca(base_dir : String)
    # Generate CA private key
    ca_key_path = "#{base_dir}/ca/ca.key"
    ca_cert_path = "#{base_dir}/ca/ca.crt"

    # Use openssl command to generate CA key and certificate
    system("openssl genpkey -algorithm RSA -out #{ca_key_path} -pkeyopt rsa_keygen_bits:2048")

    # Generate self-signed CA certificate
    system("openssl req -new -x509 -days 365 -key #{ca_key_path} -out #{ca_cert_path} -subj '/CN=Test CA'")
  end

  private def self.generate_server_cert(base_dir : String, server_name : String)
    server_key_path = "#{base_dir}/#{server_name}/server.key"
    server_csr_path = "#{base_dir}/#{server_name}/server.csr"
    server_cert_path = "#{base_dir}/#{server_name}/server.crt"
    ca_key_path = "#{base_dir}/ca/ca.key"
    ca_cert_path = "#{base_dir}/ca/ca.crt"

    # Generate server private key
    system("openssl genpkey -algorithm RSA -out #{server_key_path} -pkeyopt rsa_keygen_bits:2048")

    # Generate certificate signing request
    system("openssl req -new -key #{server_key_path} -out #{server_csr_path} -subj '/CN=#{server_name}.test'")

    # Create extension config for SAN
    ext_config_path = "#{base_dir}/#{server_name}/san.conf"
    File.write(ext_config_path, "subjectAltName = DNS:localhost,IP:127.0.0.1")

    # Generate server certificate signed by CA
    system("openssl x509 -req -in #{server_csr_path} -CA #{ca_cert_path} -CAkey #{ca_key_path} " +
           "-CAcreateserial -out #{server_cert_path} -days 365 -extfile #{ext_config_path}")

    # Clean up CSR
    File.delete(server_csr_path) if File.exists?(server_csr_path)
  end
end
