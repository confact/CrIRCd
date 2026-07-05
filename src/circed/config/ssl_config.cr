require "yaml"

module Circed
  class Config
    class SSLConfig
      include YAML::Serializable

      # Whether SSL is enabled
      getter? enabled : Bool = false

      # Port for SSL connections (typically 6697)
      getter port : Int32 = 6697

      # Path to SSL certificate file
      getter cert_file : String?

      # Path to SSL private key file
      getter key_file : String?

      # Path to CA certificate file for verification
      getter ca_file : String?

      # Whether to verify client certificates
      getter? verify_mode : Bool = false

      # Whether to allow STARTTLS upgrade
      getter? starttls : Bool = true

      # Required for server-to-server SSL connections
      getter? require_ssl_for_servers : Bool = false

      def valid?
        return true unless enabled?

        # Certificate file is required when SSL is enabled
        return false unless cert_file_path = cert_file
        return false unless File.exists?(cert_file_path)

        # Key file is required when SSL is enabled
        return false unless key_file_path = key_file
        return false unless File.exists?(key_file_path)

        # If CA file is specified, it must exist
        if ca_file_path = ca_file
          return false unless File.exists?(ca_file_path)
        end

        # Try to load and validate the certificate and key
        begin
          # Check if certificate can be read
          cert_content = File.read(cert_file_path)
          cert_content.empty?

          # Check if key can be read
          key_content = File.read(key_file_path)
          key_content.empty?

          true
        rescue ex
          Log.error { "SSL validation error: #{ex.message}" }
          false
        end
      end
    end
  end
end
