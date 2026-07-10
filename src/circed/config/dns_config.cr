require "yaml"

module Circed
  class Config
    struct DNSConfig
      include YAML::Serializable

      getter? enabled : Bool = true
      getter server : String = "8.8.8.8"
      getter port : Int32 = 53
      getter workers : Int32 = 4
      getter queue_size : Int32 = 1024
      getter timeout_seconds : Int32 = 1
      getter registration_wait_ms : Int32 = 100
      getter cache_ttl_seconds : Int32 = 3600
      getter negative_cache_ttl_seconds : Int32 = 300

      def initialize
      end
    end
  end
end
