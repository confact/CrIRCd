module Circed
  module Services
    # Rate limiter for IRC commands to prevent flooding
    class RateLimiter
      # Per-client rate limiting configuration
      DEFAULT_MAX_COMMANDS = 10
      DEFAULT_TIME_WINDOW = 60 # seconds
      DEFAULT_BURST_SIZE = 5

      # Different rate limits for different command types
      COMMAND_LIMITS = {
        "PRIVMSG" => {max_commands: 5, time_window: 10},
        "NOTICE"  => {max_commands: 5, time_window: 10},
        "JOIN"    => {max_commands: 3, time_window: 10},
        "PART"    => {max_commands: 3, time_window: 10},
        "NICK"    => {max_commands: 2, time_window: 30},
        "WHOIS"   => {max_commands: 3, time_window: 10},
        "WHO"     => {max_commands: 2, time_window: 10},
        "NAMES"   => {max_commands: 2, time_window: 10},
        "LIST"    => {max_commands: 1, time_window: 30},
        "TOPIC"   => {max_commands: 2, time_window: 10},
        "MODE"    => {max_commands: 3, time_window: 10},
        "KICK"    => {max_commands: 2, time_window: 10},
        "INVITE"  => {max_commands: 2, time_window: 10},
      }

      # Track command counts per client
      @@client_commands = Hash(String, Hash(String, Array(Time))).new

      def self.check_rate_limit(client_id : String, command : String) : Bool
        now = Time.utc
        
        # Initialize client tracking if not exists
        @@client_commands[client_id] ||= Hash(String, Array(Time)).new
        
        # Get command history for this client
        command_history = @@client_commands[client_id][command]? || Array(Time).new
        
        # Get limits for this command
        limits = COMMAND_LIMITS[command]?
        max_commands = limits ? limits[:max_commands] : DEFAULT_MAX_COMMANDS
        time_window = limits ? limits[:time_window] : DEFAULT_TIME_WINDOW
        
        # Remove old commands outside time window
        command_history.reject! { |time| now - time > time_window.seconds }
        
        # Check if rate limit exceeded
        if command_history.size >= max_commands
          return false
        end
        
        # Add current command to history
        command_history << now
        @@client_commands[client_id][command] = command_history
        
        true
      end

      def self.is_rate_limited?(client_id : String, command : String) : Bool
        !check_rate_limit(client_id, command)
      end

      def self.get_remaining_quota(client_id : String, command : String) : Int32
        now = Time.utc
        
        # Initialize client tracking if not exists
        @@client_commands[client_id] ||= Hash(String, Array(Time)).new
        
        # Get command history for this client
        command_history = @@client_commands[client_id][command]? || Array(Time).new
        
        # Get limits for this command
        limits = COMMAND_LIMITS[command]?
        max_commands = limits ? limits[:max_commands] : DEFAULT_MAX_COMMANDS
        time_window = limits ? limits[:time_window] : DEFAULT_TIME_WINDOW
        
        # Remove old commands outside time window
        command_history.reject! { |time| now - time > time_window.seconds }
        
        # Return remaining quota
        max_commands - command_history.size
      end

      def self.get_reset_time(client_id : String, command : String) : Time?
        # Initialize client tracking if not exists
        @@client_commands[client_id] ||= Hash(String, Array(Time)).new
        
        # Get command history for this client
        command_history = @@client_commands[client_id][command]? || Array(Time).new
        
        return nil if command_history.empty?
        
        # Get limits for this command
        limits = COMMAND_LIMITS[command]?
        time_window = limits ? limits[:time_window] : DEFAULT_TIME_WINDOW
        
        # Return when the oldest command will expire
        command_history.first + time_window.seconds
      end

      def self.clear_client_history(client_id : String) : Void
        @@client_commands.delete(client_id)
      end

      def self.cleanup_old_entries : Void
        now = Time.utc
        
        @@client_commands.each do |client_id, client_commands|
          client_commands.each do |command, command_history|
            # Get limits for this command
            limits = COMMAND_LIMITS[command]?
            time_window = limits ? limits[:time_window] : DEFAULT_TIME_WINDOW
            
            # Remove old commands
            command_history.reject! { |time| now - time > time_window.seconds }
            
            # Remove empty command histories
            client_commands.delete(command) if command_history.empty?
          end
          
          # Remove empty client histories
          @@client_commands.delete(client_id) if client_commands.empty?
        end
      end

      def self.get_global_stats : Hash(String, Int32)
        total_clients = @@client_commands.size
        total_commands = @@client_commands.values.sum(&.values.sum(&.size))
        
        {
          "total_clients" => total_clients,
          "total_commands_tracked" => total_commands,
        }
      end

      def self.get_client_stats(client_id : String) : Hash(String, Int32)
        client_commands = @@client_commands[client_id]?
        return Hash(String, Int32).new unless client_commands
        
        stats = Hash(String, Int32).new
        client_commands.each do |command, history|
          stats[command] = history.size
        end
        stats
      end

      # Special handling for burst commands during registration
      def self.is_registration_command?(command : String) : Bool
        ["NICK", "USER", "PASS", "SERVER"].includes?(command)
      end

      def self.should_rate_limit?(command : String) : Bool
        # Don't rate limit certain system commands
        !["PING", "PONG", "ERROR", "QUIT"].includes?(command)
      end
    end
  end
end 