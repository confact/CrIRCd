module Circed
  class Config
    include YAML::Serializable

    getter host : String
    getter port : Int32
    getter created : Time = Time.utc
    getter max_users : Int32
    getter link_password : String
    getter server_password : String? = nil
    getter network : String
    getter linked_servers : Array(LinkedServer) = [] of LinkedServer
  end
end
