module Circed
  module Network
    # High-performance IRC message parser optimized for server-to-server communication
    # Uses efficient string scanning and minimal allocations
    class FastMessageParser
      # Pre-allocated buffer for message parsing
      PARSE_BUFFER_SIZE = 1024
      @@parse_buffer = Bytes.new(PARSE_BUFFER_SIZE)

      # Message component indices for efficient parsing
      enum Component
        Prefix
        Command
        Params
      end

      # Optimized message structure with minimal allocations
      struct ParsedMessage
        getter prefix : String?
        getter command : String
        getter params : Array(String)
        getter raw_line : String

        def initialize(@prefix : String?, @command : String, @params : Array(String), @raw_line : String)
        end

        # Fast hostmask parsing for server messages
        def source_nick : String?
          return nil unless prefix = @prefix
          return nil unless prefix.includes?('!')

          # Find the first '!' character efficiently
          exclamation_pos = prefix.index('!')
          return nil unless exclamation_pos

          prefix[0...exclamation_pos]
        end

        def source_user : String?
          return nil unless prefix = @prefix
          start_pos = prefix.index('!')
          end_pos = prefix.index('@')
          return nil unless start_pos && end_pos && start_pos < end_pos

          prefix[(start_pos + 1)...end_pos]
        end

        def source_host : String?
          return nil unless prefix = @prefix
          at_pos = prefix.index('@')
          return nil unless at_pos

          prefix[(at_pos + 1)..-1]
        end

        # Get trailing parameter (after ':')
        def trailing_param : String?
          return nil if @params.empty?

          last_param = @params.last
          last_param.starts_with?(':') ? last_param[1..-1] : nil
        end

        # Check if this is a server-to-server message
        def server_message? : Bool
          return false unless prefix = @prefix
          # Server messages typically don't contain '!' (no user@host format)
          !prefix.includes?('!')
        end
      end

      # Parse IRC message with optimized string operations
      def self.parse(line : String) : ParsedMessage?
        return nil if line.empty?

        # Remove trailing whitespace efficiently
        line = line.rstrip

        # Initialize parsing state
        pos = 0
        prefix : String? = nil
        command : String
        params = [] of String

        # Parse prefix if present (starts with ':')
        if line.size > 0 && line[0] == ':'
          prefix_end = line.index(' ', pos + 1)
          return nil unless prefix_end

          prefix = line[1...prefix_end]
          pos = prefix_end + 1
        end

        # Skip whitespace
        while pos < line.size && line[pos] == ' '
          pos += 1
        end
        return nil if pos >= line.size

        # Parse command (up to first space)
        command_start = pos
        while pos < line.size && line[pos] != ' '
          pos += 1
        end

        command = line[command_start...pos]
        return nil if command.empty?

        # Parse parameters
        while pos < line.size
          # Skip whitespace
          while pos < line.size && line[pos] == ' '
            pos += 1
          end
          break if pos >= line.size

          # Check for trailing parameter (starts with ':')
          if line[pos] == ':'
            # Everything from here to end is the trailing parameter
            params << line[pos..-1]
            break
          end

          # Parse regular parameter (up to next space)
          param_start = pos
          while pos < line.size && line[pos] != ' '
            pos += 1
          end

          params << line[param_start...pos]
        end

        ParsedMessage.new(prefix, command, params, line)
      end

      # Batch parse multiple messages for better performance
      def self.parse_batch(lines : Array(String)) : Array(ParsedMessage)
        results = Array(ParsedMessage).new(initial_capacity: lines.size)

        lines.each do |line|
          if parsed = parse(line)
            results << parsed
          end
        end

        results
      end

      # Parse only the command part for routing decisions (very fast)
      def self.parse_command_only(line : String) : String?
        return nil if line.empty?

        pos = 0

        # Skip prefix if present
        if line[0] == ':'
          prefix_end = line.index(' ', pos + 1)
          return nil unless prefix_end
          pos = prefix_end + 1
        end

        # Skip whitespace
        while pos < line.size && line[pos] == ' '
          pos += 1
        end
        return nil if pos >= line.size

        # Extract command
        command_start = pos
        while pos < line.size && line[pos] != ' '
          pos += 1
        end

        line[command_start...pos]
      end

      # Check if message is a high-priority server command
      def self.high_priority?(command : String) : Bool
        case command.upcase
        when "SQUIT", "KILL", "ERROR", "PING", "PONG"
          true
        else
          false
        end
      end

      # Validate message format without full parsing
      def self.valid_format?(line : String) : Bool
        return false if line.empty? || line.size > 512

        # Check for basic IRC format compliance
        pos = 0

        # Skip optional prefix
        if line[0] == ':'
          prefix_end = line.index(' ', 1)
          return false unless prefix_end
          pos = prefix_end + 1
        end

        # Must have command
        return false if pos >= line.size

        # Check command format (letters/numbers only)
        command_start = pos
        while pos < line.size && line[pos] != ' '
          char = line[pos]
          return false unless char.ascii_alphanumeric?
          pos += 1
        end

        # Command must not be empty
        pos > command_start
      end
    end
  end
end