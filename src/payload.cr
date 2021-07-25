module Circed
  struct Payload
    getter message_type : String
    getter message : String
    getter receiver : String?

    def self.parse_message(message : String) : Payload?
      return nil if message.empty?
      messages = message.split(" ", 2)
      action_type = messages.first
      message = messages[1]

      return self.new(action_type, message) if action_type != "PRIVMSG"
      privmsg_messages = message.split(" ", 2)
      receiver = privmsg_messages.first

      self.new(action_type, receiver, privmsg_messages[1])
    end

    def initialize(@message_type, @message); end
    def initialize(@message_type, @receiver, @message); end
  end
end
