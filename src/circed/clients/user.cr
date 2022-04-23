module Circed
  class User

    getter client : Client?

    getter mode : String
    getter name : String
    getter realname : String

    def initialize(@client : Client?, @mode, @name, @realname)
    end

    def to_s
      "#{name} #{mode} :#{realname}"
    end
  end
end
