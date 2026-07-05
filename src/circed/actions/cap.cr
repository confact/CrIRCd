require "./base_action"

module Circed
  class Actions::Cap < Actions::BaseAction
    SUPPORTED_CAPS = [] of String

    protected def self.execute_action(sender : Client, subcommand : String, capabilities : String? = nil) : Nil
      case subcommand.upcase
      when "LS"
        # List supported capabilities
        handle_cap_ls(sender, capabilities)
      when "REQ"
        # Request capabilities
        handle_cap_req(sender, capabilities)
      when "END"
        # End capability negotiation
        handle_cap_end(sender)
      when "LIST"
        # List currently enabled capabilities
        handle_cap_list(sender)
      else
        send_error(sender, Numerics::ERR_UNKNOWNCOMMAND, "CAP", ":Unknown CAP subcommand")
      end
    end

    protected def self.validate_sender(_sender : Client) : Bool
      true
    end

    private def self.handle_cap_ls(sender : Client, version : String?)
      caps_string = SUPPORTED_CAPS.join(" ")

      if version && version.to_i >= 302
        # Multi-line LS response for CAP 302+ - end with final message
        sender.send_message(Server.clean_name, "CAP", "*", "LS", ":#{caps_string}")
      else
        # Single-line LS response
        sender.send_message(Server.clean_name, "CAP", "*", "LS", ":#{caps_string}")
      end

      # Note: Don't auto-complete registration here
      # Let the client send NICK and USER commands first, then complete registration
      # when both are received (handled in the NICK and USER command handlers)
    end

    private def self.handle_cap_req(sender : Client, capabilities : String?)
      return unless capabilities

      requested_caps = capabilities.split(" ")

      # Check which capabilities we can support
      ack_caps = [] of String
      nak_caps = [] of String

      requested_caps.each do |cap|
        if SUPPORTED_CAPS.includes?(cap)
          ack_caps << cap
        else
          nak_caps << cap
        end
      end

      # Send ACK for supported capabilities
      unless ack_caps.empty?
        sender.send_message(Server.clean_name, "CAP", "*", "ACK", ":#{ack_caps.join(" ")}")
      end

      # Send NAK for unsupported capabilities
      unless nak_caps.empty?
        sender.send_message(Server.clean_name, "CAP", "*", "NAK", ":#{nak_caps.join(" ")}")
      end
    end

    private def self.handle_cap_end(sender : Client)
      # End capability negotiation - client is ending CAP negotiation
      # Don't send CAP END back to client (that's what they sent to us)

      # If we have both nickname and user info, complete registration
      if sender.nickname && sender.user && !sender.registered?
        sender.complete_registration
      end
    end

    private def self.handle_cap_list(sender : Client)
      # List currently enabled capabilities (for now, none are enabled by default)
      sender.send_message(Server.clean_name, "CAP", "*", "LIST", ":")
    end
  end
end
