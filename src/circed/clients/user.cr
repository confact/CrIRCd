module Circed
  struct User
    getter mode : String
    getter name : String
    getter realname : String

    def initialize(@mode, @name, @realname)
    end

    def to_s(io : IO)
      io << name
      io << " "
      io << mode
      io << " :"
      io << realname
    end
  end
end
