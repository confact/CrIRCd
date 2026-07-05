module Circed
  class OperatorConfig
    include YAML::Serializable

    getter name : String
    getter password : String
    getter hosts : Array(String) = ["*"] of String
    getter? local : Bool = false

    def matches?(oper_name : String, oper_password : String, client_masks : Array(String)) : Bool
      return false unless name == oper_name && password == oper_password

      hosts.any? do |host_pattern|
        client_masks.any? { |client_mask| wildcard_match?(host_pattern, client_mask) }
      end
    end

    def mode : Char
      local? ? 'O' : 'o'
    end

    private def wildcard_match?(pattern : String, value : String) : Bool
      pattern_index = 0
      value_index = 0
      star_index = -1
      backtrack_value_index = 0

      while value_index < value.bytesize
        if pattern_index < pattern.bytesize &&
           wildcard_byte_matches?(pattern.byte_at(pattern_index), value.byte_at(value_index))
          pattern_index += 1
          value_index += 1
        elsif pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == '*'.ord.to_u8
          star_index = pattern_index
          backtrack_value_index = value_index
          pattern_index += 1
        elsif star_index >= 0
          pattern_index = star_index + 1
          backtrack_value_index += 1
          value_index = backtrack_value_index
        else
          return false
        end
      end

      while pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == '*'.ord.to_u8
        pattern_index += 1
      end

      pattern_index == pattern.bytesize
    end

    private def wildcard_byte_matches?(pattern_byte : UInt8, value_byte : UInt8) : Bool
      pattern_byte == '?'.ord.to_u8 || ascii_downcase(pattern_byte) == ascii_downcase(value_byte)
    end

    private def ascii_downcase(byte : UInt8) : UInt8
      value = byte.to_i
      return (value + 32).to_u8 if value >= 65 && value <= 90

      byte
    end
  end
end
