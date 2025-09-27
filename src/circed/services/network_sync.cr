require "../servers/server_handler"

module Circed::Services
  # Handles synchronization of services data across the IRC network
  class NetworkSync
    # Propagate user registration to all linked servers
    def self.broadcast_user_registration(nickname : String, password_hash : String, email : String?)
      message = "SVSREGISTER #{nickname} #{password_hash}"
      message += " #{email}" if email
      broadcast_to_network(message)
    end

    # Propagate user identification status
    def self.broadcast_user_identification(nickname : String, identified : Bool)
      status = identified ? "IDENTIFIED" : "UNIDENTIFIED"
      broadcast_to_network("SVSIDENTIFY #{nickname} #{status}")
    end

    # Propagate channel registration to all linked servers
    def self.broadcast_channel_registration(channel_name : String, founder : String, topic : String?, modes : String)
      topic_part = topic ? " :#{topic}" : ""
      broadcast_to_network("SVSREGCHAN #{channel_name} #{founder} #{modes}#{topic_part}")
    end

    # Propagate channel access changes
    def self.broadcast_channel_access(channel_name : String, nickname : String, access_level : Int32, added_by : String)
      broadcast_to_network("SVSACCESS #{channel_name} #{nickname} #{access_level} #{added_by}")
    end

    # Propagate channel access removal
    def self.broadcast_channel_access_removal(channel_name : String, nickname : String)
      broadcast_to_network("SVSREMACCESS #{channel_name} #{nickname}")
    end

    # Propagate channel drop
    def self.broadcast_channel_drop(channel_name : String)
      broadcast_to_network("SVSDROPCHAN #{channel_name}")
    end

    # Handle incoming services synchronization messages
    def self.handle_services_message(sender_server : String, command : String, params : Array(String))
      case command.upcase
      when "SVSREGISTER"
        handle_user_registration_sync(params)
      when "SVSIDENTIFY"
        handle_user_identification_sync(params)
      when "SVSREGCHAN"
        handle_channel_registration_sync(params)
      when "SVSACCESS"
        handle_channel_access_sync(params)
      when "SVSREMACCESS"
        handle_channel_access_removal_sync(params)
      when "SVSDROPCHAN"
        handle_channel_drop_sync(params)
      when "SVSQUERY"
        handle_services_query(sender_server, params)
      when "SVSRESPONSE"
        handle_services_response(params)
      end
    end

    # Request services data from other servers (during server linking)
    def self.request_services_sync(target_server : String)
      # Request all registered users
      send_to_server(target_server, "SVSQUERY USERS")
      # Request all registered channels
      send_to_server(target_server, "SVSQUERY CHANNELS")
    end

    # Send services data to a newly linked server
    def self.send_full_sync(target_server : String)
      # Send all registered users
      Database.db.query_all("SELECT nickname, password_hash, email FROM registered_users") do |result_set|
        nickname = result_set.read(String)
        password_hash = result_set.read(String)
        email = result_set.read(String?)

        message = "SVSREGISTER #{nickname} #{password_hash}"
        message += " #{email}" if email
        send_to_server(target_server, message)
      end

      # Send all registered channels
      Database.db.query_all("SELECT channel_name, founder, topic, modes FROM registered_channels") do |result_set|
        channel_name = result_set.read(String)
        founder = result_set.read(String)
        topic = result_set.read(String?)
        modes = result_set.read(String)

        topic_part = topic ? " :#{topic}" : ""
        send_to_server(target_server, "SVSREGCHAN #{channel_name} #{founder} #{modes}#{topic_part}")
      end

      # Send all channel access entries
      Database.db.query_all("SELECT channel_name, nickname, access_level, added_by FROM channel_access") do |result_set|
        channel_name = result_set.read(String)
        nickname = result_set.read(String)
        access_level = result_set.read(Int32)
        added_by = result_set.read(String)

        send_to_server(target_server, "SVSACCESS #{channel_name} #{nickname} #{access_level} #{added_by}")
      end
    end

    private def self.handle_user_registration_sync(params : Array(String))
      return unless params.size >= 2

      nickname = params[0]
      password_hash = params[1]
      email = params[2]? if params.size > 2

      # Insert if not exists (avoid conflicts)
      Database.db.exec(
        "INSERT OR IGNORE INTO registered_users (nickname, password_hash, email) VALUES (?, ?, ?)",
        nickname, password_hash, email
      )
    end

    private def self.handle_user_identification_sync(params : Array(String))
      return unless params.size >= 2

      nickname = params[0]
      status = params[1]

      # Update identification status in memory (you might want to store this)
      # For now, this just ensures the user exists in the database
      if status == "IDENTIFIED"
        Log.debug { "User #{nickname} identified on remote server" }
      end
    end

    private def self.handle_channel_registration_sync(params : Array(String))
      return unless params.size >= 3

      channel_name = params[0]
      founder = params[1]
      modes = params[2]
      topic = params[3]? if params.size > 3

      # Insert if not exists
      Database.db.exec(
        "INSERT OR IGNORE INTO registered_channels (channel_name, founder, topic, modes) VALUES (?, ?, ?, ?)",
        channel_name, founder, topic, modes
      )
    end

    private def self.handle_channel_access_sync(params : Array(String))
      return unless params.size >= 4

      channel_name = params[0]
      nickname = params[1]
      access_level = params[2].to_i32
      added_by = params[3]

      # Insert or update access
      Database.db.exec(
        "INSERT OR REPLACE INTO channel_access (channel_name, nickname, access_level, added_by) VALUES (?, ?, ?, ?)",
        channel_name, nickname, access_level, added_by
      )
    end

    private def self.handle_channel_access_removal_sync(params : Array(String))
      return unless params.size >= 2

      channel_name = params[0]
      nickname = params[1]

      Database.db.exec(
        "DELETE FROM channel_access WHERE channel_name = ? AND nickname = ?",
        channel_name, nickname
      )
    end

    private def self.handle_channel_drop_sync(params : Array(String))
      return unless params.size >= 1

      channel_name = params[0]

      # Remove channel and all access entries
      Database.db.exec("DELETE FROM registered_channels WHERE channel_name = ?", channel_name)
      Database.db.exec("DELETE FROM channel_access WHERE channel_name = ?", channel_name)
    end

    private def self.handle_services_query(sender_server : String, params : Array(String))
      return unless params.size >= 1

      query_type = params[0].upcase

      case query_type
      when "USERS"
        # Send all registered users to requesting server
        send_full_sync(sender_server)
      when "CHANNELS"
        # Already included in send_full_sync
      end
    end

    private def self.handle_services_response(params : Array(String))
      # Handle responses to our queries
      # Implementation depends on what data format you expect
    end

    # Broadcast a message to all linked servers
    def self.broadcast_to_network(message : String)
      ServerHandler.servers.each do |link_server|
        link_server.safe_send(message)
      end
    end

    # Send a message to a specific server
    def self.send_to_server(server_name : String, message : String)
      server = ServerHandler.servers.find { |srv| srv.name == server_name }
      server.try(&.safe_send(message))
    end
  end
end
