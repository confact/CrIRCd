require "./base_action"

module Circed
  class Actions::Cap < Actions::BaseAction
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

    private def self.handle_cap_ls(sender : Client, version : String?)
      # Basic capabilities we support
      supported_caps = [
        "multi-prefix",    # Multiple prefix support
        "extended-join",   # Extended JOIN messages
        "account-notify",  # Account change notifications
        "away-notify",     # Away status notifications
        "chghost",         # Host change support
        "userhost-in-names", # Userhost in NAMES
        "cap-notify",      # Capability change notifications
        "server-time",     # Server timestamps
        "message-tags",    # Message tags support
        "batch",           # Batch message support
        "labeled-response", # Labeled responses
        "sasl"            # SASL authentication
      ]

      caps_string = supported_caps.join(" ")

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
      supported_caps = [
        "multi-prefix", "extended-join", "account-notify", "away-notify",
        "chghost", "userhost-in-names", "cap-notify", "server-time",
        "message-tags", "batch", "labeled-response", "sasl"
      ]

      # Check which capabilities we can support
      ack_caps = [] of String
      nak_caps = [] of String

      requested_caps.each do |cap|
        if supported_caps.includes?(cap)
          ack_caps << cap
        else
          nak_caps << cap
        end
      end

      # Send ACK for supported capabilities
      if ack_caps.any?
        sender.send_message(Server.clean_name, "CAP", "*", "ACK", ":#{ack_caps.join(" ")}")
      end

      # Send NAK for unsupported capabilities
      if nak_caps.any?
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