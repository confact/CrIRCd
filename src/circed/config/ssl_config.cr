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
        if cert_file_path = cert_file
          if key_file_path = key_file
            File.exists?(cert_file_path) && File.exists?(key_file_path)
          else
            false
          end
        else
          false
        end
      end
    end
  end
end
