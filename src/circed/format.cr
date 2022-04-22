module Circed
  class Format
    def self.format_message(params)
      params.join(" ")
    end

    def self.format_server_message(server : String, *params)
      String.build do |io|
        io << ":"
        io << server
        io << " "
        io << format_message(params)
        io << "\n"
      end
    end

    def self.format_user_message(server : String, *params)
      String.build do |io|
        io << server
        io << " "
        io << format_message(params)
        io << "\n"
      end
    end
  end
end
