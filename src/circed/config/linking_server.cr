module Circed
  struct LinkedServer
    include YAML::Serializable

    getter host : String
    getter server_name : String? = nil
    getter port : Int32
    getter link_password : String
    getter? use_ssl : Bool = false
    getter? verify_ssl : Bool = false

    def irc_name : String
      server_name || host
    end
  end
end
