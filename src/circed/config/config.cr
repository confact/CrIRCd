require "./dns_config"
require "./operator_config"
require "./ssl_config"

module Circed
  class Config
    include YAML::Serializable

    getter host : String
    getter server_name : String? = nil
    getter port : Int32
    getter created : Time = Time.utc
    getter max_users : Int32
    getter link_password : String
    getter server_password : String? = nil
    getter line_database : String = "data/lines.yml"
    getter? allow_die : Bool = false
    getter? allow_restart : Bool = false
    getter network : String
    getter linked_servers : Array(LinkedServer) = [] of LinkedServer
    getter operators : Array(OperatorConfig) = [] of OperatorConfig
    getter ssl : SSLConfig?
    getter dns : DNSConfig = DNSConfig.new

    def validate_ssl!
      if ssl_config = ssl
        if ssl_config.enabled? && !ssl_config.valid?
          raise "Invalid SSL configuration: certificate and key files must exist"
        end
      end
    end
  end
end
