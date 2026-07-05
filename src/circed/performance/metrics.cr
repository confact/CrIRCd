module Circed
  module Performance
    # Performance monitoring and metrics collection
    # Designed to be lightweight and non-intrusive
    class Metrics
      # Metric counters using atomic operations for thread safety
      @@message_count = Atomic(UInt64).new(0_u64)
      @@user_connections = Atomic(UInt32).new(0_u32)
      @@server_connections = Atomic(UInt32).new(0_u32)
      @@channel_operations = Atomic(UInt64).new(0_u64)
      @@memory_allocations = Atomic(UInt64).new(0_u64)
      @@command_counts = Hash(String, UInt64).new(0_u64)
      @@command_counts_mutex = Mutex.new

      # Timing measurements
      @@burst_times = [] of Time::Span
      @@message_processing_times = [] of Time::Span
      @@netsplit_times = [] of Time::Span

      # Memory usage tracking
      @@peak_memory_usage : UInt64 = 0_u64
      @@last_gc_time = Time.monotonic

      # Performance thresholds
      MAX_BURST_TIME    = 5.seconds
      MAX_MESSAGE_TIME  = 100.milliseconds
      MAX_NETSPLIT_TIME = 10.seconds

      # Increment message counter atomically
      def self.increment_messages(count : UInt64 = 1_u64)
        @@message_count.add(count)
      end

      def self.increment_user_connections
        @@user_connections.add(1_u32)
      end

      def self.decrement_user_connections
        @@user_connections.sub(1_u32)
      end

      def self.increment_server_connections
        @@server_connections.add(1_u32)
      end

      def self.decrement_server_connections
        @@server_connections.sub(1_u32)
      end

      def self.increment_channel_operations
        @@channel_operations.add(1_u64)
      end

      def self.increment_command(command : String)
        normalized_command = command.upcase
        @@command_counts_mutex.synchronize do
          @@command_counts[normalized_command] += 1_u64
        end
      end

      def self.command_counts : Hash(String, UInt64)
        @@command_counts_mutex.synchronize do
          @@command_counts.dup
        end
      end

      # Time a block execution and categorize by operation type
      def self.time_burst(&)
        start_time = Time.monotonic
        result = yield
        duration = Time.monotonic - start_time

        @@burst_times << duration
        # Keep only last 100 measurements
        @@burst_times.shift if @@burst_times.size > 100

        if duration > MAX_BURST_TIME
          Log.warn { "Slow burst operation: #{duration}" }
        end

        result
      end

      def self.time_message_processing(&)
        start_time = Time.monotonic
        result = yield
        duration = Time.monotonic - start_time

        @@message_processing_times << duration
        @@message_processing_times.shift if @@message_processing_times.size > 1000

        if duration > MAX_MESSAGE_TIME
          Log.warn { "Slow message processing: #{duration}" }
        end

        result
      end

      def self.time_netsplit(&)
        start_time = Time.monotonic
        result = yield
        duration = Time.monotonic - start_time

        @@netsplit_times << duration
        @@netsplit_times.shift if @@netsplit_times.size > 50

        if duration > MAX_NETSPLIT_TIME
          Log.warn { "Slow netsplit operation: #{duration}" }
        end

        result
      end

      # Get current metrics snapshot
      def self.snapshot
        {
          messages_processed: @@message_count.get,
          active_users:       @@user_connections.get,
          active_servers:     @@server_connections.get,
          channel_operations: @@channel_operations.get,
          avg_burst_time:     calculate_average(@@burst_times),
          avg_message_time:   calculate_average(@@message_processing_times),
          avg_netsplit_time:  calculate_average(@@netsplit_times),
          memory_usage:       GC.stats.heap_size,
        }
      end

      # Reset all counters (for testing or periodic cleanup)
      def self.reset
        @@message_count.set(0_u64)
        @@user_connections.set(0_u32)
        @@server_connections.set(0_u32)
        @@channel_operations.set(0_u64)
        @@memory_allocations.set(0_u64)
        @@command_counts_mutex.synchronize do
          @@command_counts.clear
        end
        @@burst_times.clear
        @@message_processing_times.clear
        @@netsplit_times.clear
      end

      # Check if performance is degraded
      def self.performance_warning? : Bool
        return true if @@burst_times.any? { |time| time > MAX_BURST_TIME }
        return true if @@message_processing_times.count { |time| time > MAX_MESSAGE_TIME } > 10
        return true if @@netsplit_times.any? { |time| time > MAX_NETSPLIT_TIME }

        # Check memory pressure
        current_memory = GC.stats.heap_size
        return true if current_memory > @@peak_memory_usage * 2

        false
      end

      # Suggest optimizations based on current metrics
      def self.optimization_suggestions : Array(String)
        suggestions = [] of String

        if @@message_processing_times.sum(&.total_seconds) > 1.0
          suggestions << "Consider message batching or async processing"
        end

        if @@burst_times.any? { |time| time > 3.seconds }
          suggestions << "Burst protocol may need optimization"
        end

        if GC.stats.heap_size > 100_000_000 # 100MB in bytes
          suggestions << "Consider periodic cache cleanup"
        end

        if @@user_connections.get > 1000 && calculate_average(@@message_processing_times) > 10.milliseconds
          suggestions << "High user load detected, consider connection pooling"
        end

        suggestions
      end

      private def self.calculate_average(times : Array(Time::Span)) : Time::Span
        return Time::Span.zero if times.empty?
        total = times.sum
        Time::Span.new(nanoseconds: (total.total_nanoseconds / times.size).to_i)
      end
    end
  end
end
