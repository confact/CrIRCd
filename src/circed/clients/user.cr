module Circed
  class User
    getter client : Client?

    property mode : String
    getter name : String
    getter realname : String

    def initialize(@client : Client?, @mode, @name, @realname)
    end

    def to_s(io : IO)
      io << name
      io << " "
      io << mode
      io << " :"
      io << realname
    end

    def operator?
      mode.include? "o"
    end

    def wallops?
      mode.include? "w"
    end
  end
end
