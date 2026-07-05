require "file_utils"

# SSL certificate generator for testing
class SSLCertificateGenerator
  CACHE_DIR = File.join(Dir.tempdir, "circed_ssl_test_certs")

  def self.generate_test_certificates(base_dir : String)
    return if certificates_complete?(base_dir)

    ensure_cached_certificates
    FileUtils.rm_rf(base_dir)
    FileUtils.mkdir_p(base_dir)
    copy_certificates(CACHE_DIR, base_dir)
  end

  private def self.ensure_cached_certificates
    return if certificates_complete?(CACHE_DIR)

    FileUtils.rm_rf(CACHE_DIR)
    create_certificates(CACHE_DIR)
  end

  private def self.create_certificates(base_dir : String)
    FileUtils.mkdir_p("#{base_dir}/ca")
    FileUtils.mkdir_p("#{base_dir}/server1")
    FileUtils.mkdir_p("#{base_dir}/server2")

    generate_ca(base_dir)
    generate_server_cert(base_dir, "server1")
    generate_server_cert(base_dir, "server2")
  end

  private def self.certificates_complete?(base_dir : String) : Bool
    %w[
      ca/ca.crt
      ca/ca.key
      server1/server.crt
      server1/server.key
      server2/server.crt
      server2/server.key
    ].all? { |path| File.exists?(File.join(base_dir, path)) }
  end

  private def self.copy_certificates(source_dir : String, target_dir : String) : Nil
    Dir.glob("#{source_dir}/**/*").each do |source|
      next if File.directory?(source)

      relative_path = source[(source_dir.size + 1)..]
      target = File.join(target_dir, relative_path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(source, target)
    end
  end

  private def self.generate_ca(base_dir : String)
    # Generate CA private key
    ca_key_path = "#{base_dir}/ca/ca.key"
    ca_cert_path = "#{base_dir}/ca/ca.crt"

    run_openssl("genpkey", "-algorithm", "RSA", "-out", ca_key_path, "-pkeyopt", "rsa_keygen_bits:2048")

    # Generate self-signed CA certificate
    run_openssl("req", "-new", "-x509", "-days", "365", "-key", ca_key_path, "-out", ca_cert_path, "-subj", "/CN=Test CA")
  end

  private def self.generate_server_cert(base_dir : String, server_name : String)
    server_key_path = "#{base_dir}/#{server_name}/server.key"
    server_csr_path = "#{base_dir}/#{server_name}/server.csr"
    server_cert_path = "#{base_dir}/#{server_name}/server.crt"
    ca_key_path = "#{base_dir}/ca/ca.key"
    ca_cert_path = "#{base_dir}/ca/ca.crt"

    # Generate server private key
    run_openssl("genpkey", "-algorithm", "RSA", "-out", server_key_path, "-pkeyopt", "rsa_keygen_bits:2048")

    # Generate certificate signing request
    run_openssl("req", "-new", "-key", server_key_path, "-out", server_csr_path, "-subj", "/CN=#{server_name}.test")

    # Create extension config for SAN
    ext_config_path = "#{base_dir}/#{server_name}/san.conf"
    File.write(ext_config_path, "subjectAltName = DNS:localhost,IP:127.0.0.1")

    # Generate server certificate signed by CA
    run_openssl(
      "x509", "-req", "-in", server_csr_path, "-CA", ca_cert_path,
      "-CAkey", ca_key_path, "-CAcreateserial", "-out", server_cert_path,
      "-days", "365", "-extfile", ext_config_path
    )

    # Clean up CSR
    File.delete(server_csr_path) if File.exists?(server_csr_path)
  end

  private def self.run_openssl(*args : String) : Nil
    status = Process.run("openssl", args: args, output: Process::Redirect::Close, error: Process::Redirect::Close)
    raise "openssl #{args.join(' ')} failed" unless status.success?
  end
end
