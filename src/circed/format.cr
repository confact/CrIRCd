module Circed
  module Format
    def self.message(prefix : String, command : String, *params) : String
      String.build do |io|
        message(io, prefix, command, *params)
      end
    end

    def self.message(io : IO, prefix : String, command : String, *params) : Nil
      message_params = Array(String).new(params.size)
      params.each do |param|
        message_params << param.to_s
      end

      if (trailing = message_params.last?) && trailing.starts_with?(':')
        message_params[-1] = trailing.lchop(':')
      end

      irc_prefix = FastIRC::Prefix.new(source: prefix.lchop(':'), user: nil, host: nil)
      FastIRC::Message.new(command, message_params, prefix: irc_prefix).to_s(io)
    end
  end
end
