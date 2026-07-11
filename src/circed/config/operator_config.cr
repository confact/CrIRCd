require "../domain/entities"

module Circed
  struct OperatorConfig
    include YAML::Serializable

    getter name : String
    getter password : String
    getter hosts : Array(String) = ["*"] of String
    getter? local : Bool = false

    def matches?(oper_name : String, oper_password : String, client_masks : Array(String)) : Bool
      return false unless name == oper_name && password == oper_password

      hosts.any? do |host_pattern|
        client_masks.any? { |client_mask| Domain::Wildcard.match?(host_pattern, client_mask) }
      end
    end

    def mode : Char
      local? ? 'O' : 'o'
    end
  end
end
