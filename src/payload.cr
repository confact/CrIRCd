module Circed
  struct Payload
    getter message_type : String
    getter message : String

    def self.parse_message(message : String) : Payload?
      return nil if message.empty?
      messages = message.split(" ", 2)
      self.new(messages.first, messages[1])
    end

    def initialize(@message_type, @message); end
  end
end
