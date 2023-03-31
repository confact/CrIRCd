module Circed
  class LinkedServer
    include YAML::Serializable

    getter host : String
    getter port : Int32
    getter link_password : String
  end
end
