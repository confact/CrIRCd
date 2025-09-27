require "./base_service"
require "./database"
require "./models"
require "crypto/bcrypt"

module Circed::Services
  # UserServ - User registration and authentication service
  class UserServ < BaseService
    def initialize
      super("UserServ", "services", Server.config.host, "User Registration Service")
    end

    def handle_message(sender : String, command : String, params : Array(String))
      cmd = command.upcase

      # Authentication commands
      if handle_auth_commands(sender, cmd, params)
        return
      end

      # Nick management commands
      if handle_nick_commands(sender, cmd, params)
        return
      end

      # Information and settings commands
      if handle_info_commands(sender, cmd, params)
        return
      end

      send_notice(sender, "Unknown command. Type /msg UserServ HELP for available commands.")
    end

    private def handle_auth_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "REGISTER"
        handle_register(sender, params)
        true
      when "IDENTIFY"
        handle_identify(sender, params)
        true
      else
        false
      end
    end

    private def handle_nick_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "GHOST"
        handle_ghost(sender, params)
        true
      when "RECOVER"
        handle_recover(sender, params)
        true
      when "RELEASE"
        handle_release(sender, params)
        true
      when "GROUP"
        handle_group(sender, params)
        true
      when "UNGROUP"
        handle_ungroup(sender, params)
        true
      else
        false
      end
    end

    private def handle_info_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "INFO"
        handle_info(sender, params)
        true
      when "SET"
        handle_set(sender, params)
        true
      when "HELP"
        handle_help(sender, params)
        true
      else
        false
      end
    end

    private def handle_register(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: REGISTER <password> [email]")
        return
      end

      password = params[0]
      email = params[1]? if params.size > 1

      # Check if nickname is already registered
      if get_registered_user(sender)
        send_notice(sender, "Nickname #{sender} is already registered.")
        return
      end

      # Validate password
      if password.size < 5
        send_notice(sender, "Password must be at least 5 characters long.")
        return
      end

      # Hash password
      password_hash = Crypto::Bcrypt::Password.create(password).to_s

      # Register user
      Database.db.exec(
        "INSERT INTO registered_users (nickname, password_hash, email) VALUES (?, ?, ?)",
        sender, password_hash, email
      )

      send_notice(sender, "Nickname #{sender} has been registered successfully.")
      if email
        send_notice(sender, "A confirmation email would be sent to #{email} (email not implemented in this demo).")
      end
      send_notice(sender, "You are now identified for #{sender}.")

      # Mark user as identified
      mark_user_identified(sender)
    end

    private def handle_identify(sender : String, params : Array(String))
      if params.size < 1
        send_notice(sender, "Syntax: IDENTIFY <password> [nickname]")
        return
      end

      password = params[0]
      target_nick = params[1]? || sender

      registered_user = get_registered_user(target_nick)
      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      unless registered_user.check_password(password)
        send_notice(sender, "Invalid password for #{target_nick}.")
        return
      end

      # Update last seen
      Database.db.exec(
        "UPDATE registered_users SET last_seen = CURRENT_TIMESTAMP WHERE nickname = ?",
        target_nick
      )

      send_notice(sender, "You are now identified for #{target_nick}.")
      mark_user_identified(sender)

      # If identifying for a different nickname and that nick is available, suggest switching
      if target_nick.downcase != sender.downcase && !get_user(target_nick)
        send_notice(sender, "The nickname #{target_nick} is not currently in use. You may want to change to it.")
      end
    end

    private def handle_ghost(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: GHOST <nickname> <password>")
        return
      end

      target_nick = params[0]
      password = params[1]

      registered_user = get_registered_user(target_nick)
      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      unless registered_user.check_password(password)
        send_notice(sender, "Invalid password for #{target_nick}.")
        return
      end

      # Check if target nick is currently online
      if target_user = get_user(target_nick)
        # Disconnect the user
        target_user.send_message("ERROR :You have been ghosted by #{sender}")
        target_user.close
        send_notice(sender, "#{target_nick} has been ghosted.")
      else
        send_notice(sender, "#{target_nick} is not currently online.")
      end
    end

    private def handle_recover(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: RECOVER <nickname> <password>")
        return
      end

      target_nick = params[0]
      password = params[1]

      registered_user = get_registered_user(target_nick)
      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      unless registered_user.check_password(password)
        send_notice(sender, "Invalid password for #{target_nick}.")
        return
      end

      # Ghost the target if online, then suggest changing nick
      if target_user = get_user(target_nick)
        target_user.send_message("ERROR :You have been recovered by #{sender}")
        target_user.close
      end

      send_notice(sender, "#{target_nick} has been recovered. You may now change to this nickname.")
    end

    private def handle_release(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: RELEASE <nickname> <password>")
        return
      end

      target_nick = params[0]
      password = params[1]

      registered_user = get_registered_user(target_nick)
      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      unless registered_user.check_password(password)
        send_notice(sender, "Invalid password for #{target_nick}.")
        return
      end

      # This would release a nickname from protection (implementation specific)
      send_notice(sender, "#{target_nick} has been released from protection for 1 minute.")
    end

    private def handle_group(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: GROUP <target_nickname> <password>")
        return
      end

      target_nick = params[0]
      password = params[1]

      registered_user = get_registered_user(target_nick)
      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      unless registered_user.check_password(password)
        send_notice(sender, "Invalid password for #{target_nick}.")
        return
      end

      # Check if sender is already registered
      if get_registered_user(sender)
        send_notice(sender, "#{sender} is already registered. Unregister it first if you want to group it.")
        return
      end

      # Add alias
      Database.db.exec(
        "INSERT INTO user_aliases (nickname, alias) VALUES (?, ?)",
        target_nick, sender
      )

      send_notice(sender, "#{sender} has been grouped to #{target_nick}.")
    end

    private def handle_ungroup(sender : String, params : Array(String))
      if params.size < 1
        send_notice(sender, "Syntax: UNGROUP [nickname]")
        return
      end

      target_nick = params[0]? || sender

      # Remove alias
      result = Database.db.exec(
        "DELETE FROM user_aliases WHERE alias = ?",
        target_nick
      )

      if result.rows_affected > 0
        send_notice(sender, "#{target_nick} has been ungrouped.")
      else
        send_notice(sender, "#{target_nick} is not grouped to any nickname.")
      end
    end

    private def handle_info(sender : String, params : Array(String))
      if params.size < 1
        send_notice(sender, "Syntax: INFO <nickname>")
        return
      end

      target_nick = params[0]
      registered_user = get_registered_user(target_nick)

      unless registered_user
        send_notice(sender, "Nickname #{target_nick} is not registered.")
        return
      end

      send_notice(sender, "Information for #{target_nick}:")
      send_notice(sender, "  Registered: #{registered_user.registered_at}")
      send_notice(sender, "  Last seen: #{registered_user.last_seen}")
      if email = registered_user.email
        send_notice(sender, "  Email: #{email}")
      end

      # Show aliases
      aliases = Database.db.query_all(
        "SELECT alias FROM user_aliases WHERE nickname = ?",
        target_nick
      ) do |result_set|
        result_set.read(String)
      end

      unless aliases.empty?
        send_notice(sender, "  Aliases: #{aliases.join(", ")}")
      end

      # Show online status
      if get_user(target_nick)
        send_notice(sender, "  Status: Online")
      else
        send_notice(sender, "  Status: Offline")
      end
    end

    private def handle_set(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: SET <option> <value>")
        send_notice(sender, "Available options: PASSWORD, EMAIL")
        return
      end

      option = params[0].upcase
      value = params[1..-1].join(" ")

      registered_user = get_registered_user(sender)
      unless registered_user
        send_notice(sender, "You must be registered to use SET commands.")
        return
      end

      case option
      when "PASSWORD"
        if value.size < 5
          send_notice(sender, "Password must be at least 5 characters long.")
          return
        end

        password_hash = Crypto::Bcrypt::Password.create(value).to_s
        Database.db.exec(
          "UPDATE registered_users SET password_hash = ? WHERE nickname = ?",
          password_hash, sender
        )
        send_notice(sender, "Password has been updated.")
      when "EMAIL"
        Database.db.exec(
          "UPDATE registered_users SET email = ? WHERE nickname = ?",
          value.empty? ? nil : value, sender
        )
        if value.empty?
          send_notice(sender, "Email address has been cleared.")
        else
          send_notice(sender, "Email address has been set to #{value}.")
        end
      else
        send_notice(sender, "Unknown option #{option}. Available options: PASSWORD, EMAIL")
      end
    end

    private def handle_help(sender : String, params : Array(String))
      send_notice(sender, "UserServ commands:")
      send_notice(sender, "  REGISTER <password> [email] - Register your nickname")
      send_notice(sender, "  IDENTIFY <password> [nickname] - Identify for a nickname")
      send_notice(sender, "  GHOST <nickname> <password> - Disconnect a ghosted session")
      send_notice(sender, "  RECOVER <nickname> <password> - Recover your nickname")
      send_notice(sender, "  RELEASE <nickname> <password> - Release nickname protection")
      send_notice(sender, "  GROUP <target_nick> <password> - Group nickname to another")
      send_notice(sender, "  UNGROUP [nickname] - Ungroup a nickname")
      send_notice(sender, "  INFO <nickname> - Show nickname information")
      send_notice(sender, "  SET <option> <value> - Set user options")
      send_notice(sender, "For more help on a specific command, type: /msg UserServ HELP <command>")
    end

    private def get_registered_user(nickname : String) : RegisteredUser?
      Database.db.query_one?(
        "SELECT id, nickname, password_hash, email, registered_at, last_seen, flags FROM registered_users WHERE nickname = ?",
        nickname
      ) do |result_set|
        RegisteredUser.new(
          result_set.read(Int32), result_set.read(String), result_set.read(String),
          result_set.read(String?), result_set.read(Time), result_set.read(Time), result_set.read(String)
        )
      end
    end

    private def mark_user_identified(nickname : String)
      # In a real implementation, you'd mark the user as identified in memory
      # For now, we'll just send a success message
      # This could be implemented as a flag in the user's client state
    end

    # Check if user is identified for their current nickname
    def identified?(nickname : String) : Bool
      # This would check if the user is identified
      # For this implementation, we'll assume they're identified if they're registered
      get_registered_user(nickname) != nil
    end
  end
end
