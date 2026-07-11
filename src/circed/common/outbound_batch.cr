module Circed
  module OutboundBatch
    def self.build(messages : Channel(String), first_message : String,
                   max_messages : Int32, max_bytes : Int32) : String
      message_count = 1
      byte_count = first_message.bytesize

      String.build(capacity: first_message.bytesize) do |io|
        io << first_message

        loop do
          break if message_count >= max_messages || byte_count >= max_bytes

          select
          when next_message = messages.receive?
            break unless next_message
            io << next_message
            message_count += 1
            byte_count += next_message.bytesize
          else
            break
          end
        end
      end
    end
  end
end
