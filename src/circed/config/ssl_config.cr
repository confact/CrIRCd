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

        return false unless cert_file_path = cert_file
        return false unless File.file?(cert_file_path) && File::Info.readable?(cert_file_path)

        return false unless key_file_path = key_file
        return false unless File.file?(key_file_path) && File::Info.readable?(key_file_path)

        if ca_file_path = ca_file
          return false unless File.file?(ca_file_path) && File::Info.readable?(ca_file_path)
        end

        true
      end
    end
  end
end
