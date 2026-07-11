module Circed
  module Domain
    module CaseMapping
      def self.normalize(name : String) : String
        name.each_byte do |byte|
          return build_normalized(name) unless fold(byte) == byte
        end
        name
      end

      private def self.build_normalized(name : String) : String
        String.build(capacity: name.bytesize) do |io|
          name.each_byte do |byte|
            io.write_byte(fold(byte))
          end
        end
      end

      def self.same?(left : String, right : String) : Bool
        return false unless left.bytesize == right.bytesize

        left_bytes = left.to_slice
        right_bytes = right.to_slice
        left.bytesize.times do |index|
          return false unless fold(left_bytes[index]) == fold(right_bytes[index])
        end
        true
      end

      def self.fold(byte : UInt8) : UInt8
        case byte
        when 65..90
          byte + 32
        when '['.ord
          '{'.ord.to_u8
        when ']'.ord
          '}'.ord.to_u8
        when '\\'.ord
          '|'.ord.to_u8
        when '~'.ord
          '^'.ord.to_u8
        else
          byte
        end
      end
    end
  end
end
