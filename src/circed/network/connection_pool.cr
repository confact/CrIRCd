require "../performance/metrics"

module Circed
  module Network
    # High-performance connection pool for IRC server connections
    # Manages server connections efficiently with automatic cleanup
    class ConnectionPool
      # Connection pool configuration
      MAX_IDLE_TIME    = 30.minutes
      MAX_CONNECTIONS  = 100
      CLEANUP_INTERVAL = 5.minutes

      # Connection state tracking
      private class ConnectionInfo
        getter server : LinkServer
        getter last_activity : Time
        getter? idle : Bool

        def initialize(@server : LinkServer)
          @last_activity = Time.utc
          @idle = false
        end

        def mark_active
          @last_activity = Time.utc
          @idle = false
        end

        def mark_idle
          @idle = true
        end

        def idle_time : Time::Span
          Time.utc - @last_activity
        end
      end

      # Thread-safe connection storage
      @@connections = Hash(String, ConnectionInfo).new
      @@mutex = Mutex.new
      @@cleanup_fiber : Fiber? = nil
      @@running = false

      # Initialize the connection pool
      def self.start
        return if @@running

        @@running = true
        start_cleanup_fiber
        Log.info { "Connection pool started" }
      end

      def self.stop
        @@running = false
        @@cleanup_fiber.try(&.enqueue)
        Log.info { "Connection pool stopped" }
      end

      # Add a connection to the pool
      def self.add_connection(server : LinkServer)
        @@mutex.synchronize do
          @@connections[server.name] = ConnectionInfo.new(server)
          Performance::Metrics.increment_server_connections
        end

        Log.debug { "Added connection #{server.name} to pool" }
      end

      # Remove a connection from the pool
      def self.remove_connection(server_name : String)
        @@mutex.synchronize do
          if @@connections.delete(server_name)
            Performance::Metrics.decrement_server_connections
            Log.debug { "Removed connection #{server_name} from pool" }
          end
        end
      end

      # Get an active connection by server name
      def self.get_connection(server_name : String) : LinkServer?
        @@mutex.synchronize do
          if info = @@connections[server_name]?
            info.mark_active
            info.server
          else
            nil
          end
        end
      end

      # Mark connection as active (for keep-alive)
      def self.mark_active(server_name : String)
        @@mutex.synchronize do
          @@connections[server_name]?.try(&.mark_active)
        end
      end

      # Get all active connections
      def self.active_connections : Array(LinkServer)
        @@mutex.synchronize do
          @@connections.values.map(&.server)
        end
      end

      # Get pool statistics
      def self.stats
        @@mutex.synchronize do
          total = @@connections.size
          idle_count = @@connections.count { |_, info| info.idle? }
          avg_idle_time = if total > 0
                            total_idle = @@connections.values.sum(&.idle_time.total_seconds)
                            (total_idle / total).seconds
                          else
                            Time::Span.zero
                          end

          {
            total_connections:  total,
            idle_connections:   idle_count,
            active_connections: total - idle_count,
            average_idle_time:  avg_idle_time,
            max_connections:    MAX_CONNECTIONS,
          }
        end
      end

      # Broadcast message to all connections efficiently
      def self.broadcast(message : String, exclude : Array(String) = [] of String)
        # Get connections outside mutex for better performance
        connections = @@mutex.synchronize do
          @@connections.select do |name, info|
            !exclude.includes?(name) && !info.server.closed?
          end.values.map(&.server)
        end

        # Send messages in parallel for better performance
        spawn do
          connections.each do |server|
            spawn { server.safe_send(message) }
          end
        end

        Performance::Metrics.increment_messages(connections.size.to_u64)
      end

      # Broadcast to specific server pattern (with wildcards)
      def self.broadcast_pattern(pattern : String, message : String)
        regex = pattern.gsub("*", ".*").gsub("?", ".")
        compiled_regex = Regex.new("^#{regex}$", Regex::Options::IGNORE_CASE)

        matching_connections = @@mutex.synchronize do
          @@connections.select do |name, info|
            compiled_regex.matches?(name) && !info.server.closed?
          end.values.map(&.server)
        end

        matching_connections.each do |server|
          spawn { server.safe_send(message) }
        end

        Performance::Metrics.increment_messages(matching_connections.size.to_u64)
      end

      # Clean up idle and dead connections
      def self.cleanup_connections
        removed = [] of String

        @@mutex.synchronize do
          @@connections.each do |name, info|
            should_remove = false

            # Remove closed connections
            if info.server.closed?
              should_remove = true
              Log.debug { "Removing closed connection: #{name}" }
              # Remove idle connections that exceeded max idle time
            elsif info.idle? && info.idle_time > MAX_IDLE_TIME
              should_remove = true
              Log.debug { "Removing idle connection: #{name} (idle for #{info.idle_time})" }
            end

            if should_remove
              removed << name
              info.server.close("Connection cleanup") unless info.server.closed?
            end
          end

          # Remove from tracking
          removed.each { |name| @@connections.delete(name) }
        end

        Performance::Metrics.decrement_server_connections if removed.size > 0
        Log.debug { "Cleaned up #{removed.size} connections" } if removed.size > 0
      end

      # Gracefully shutdown all connections
      def self.shutdown_all(reason : String = "Server shutdown")
        connections = @@mutex.synchronize { @@connections.values.map(&.server) }

        Log.info { "Shutting down #{connections.size} connections" }

        connections.each do |server|
          spawn do
            begin
              server.close(reason)
            rescue ex
              Log.warn { "Error closing connection #{server.name}: #{ex.message}" }
            end
          end
        end

        # Wait a bit for graceful shutdown
        sleep 1.second

        @@mutex.synchronize { @@connections.clear }
      end

      # Start the cleanup fiber
      private def self.start_cleanup_fiber
        @@cleanup_fiber = spawn do
          while @@running
            sleep CLEANUP_INTERVAL
            cleanup_connections
          end
        end
      end

      # Health check for all connections
      def self.health_check
        unhealthy = [] of String

        @@mutex.synchronize do
          @@connections.each do |name, info|
            if info.server.closed? || info.idle_time > MAX_IDLE_TIME
              unhealthy << name
            end
          end
        end

        unhealthy
      end

      # Force reconnection for a specific server
      def self.force_reconnect(server_name : String) : Bool
        @@mutex.synchronize do
          if info = @@connections[server_name]?
            info.server.close("Forced reconnect")
            @@connections.delete(server_name)
            true
          else
            false
          end
        end
      end
    end
  end
end
