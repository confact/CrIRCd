module Circed
  class LinkedServer
    include YAML::Serializable

    getter host : String
    getter port : Int32
    getter link_password : String
    getter? use_ssl : Bool = false
    getter? verify_ssl : Bool = false
  end
end
