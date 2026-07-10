require "deque"

module Circed
  module Performance
    # Performance monitoring and metrics collection
    # Designed to be lightweight and non-intrusive
    module Metrics
      # Metric counters using atomic operations for thread safety
      @@message_count = Atomic(UInt64).new(0_u64)
      @@channel_operations = Atomic(UInt64).new(0_u64)
      @@command_counts = Hash(String, UInt64).new(0_u64)
      @@command_counts_mutex = Mutex.new

      # Timing measurements
      @@burst_times = Deque(Time::Span).new
      @@message_processing_times = Deque(Time::Span).new
      @@netsplit_times = Deque(Time::Span).new

      # Performance thresholds
      MAX_BURST_TIME    = 5.seconds
      MAX_MESSAGE_TIME  = 100.milliseconds
      MAX_NETSPLIT_TIME = 10.seconds

      # Increment message counter atomically
      def self.increment_messages(count : UInt64 = 1_u64)
        @@message_count.add(count)
      end

      def self.increment_channel_operations
        @@channel_operations.add(1_u64)
      end

      def self.increment_command(command : String)
        normalized_command = command.upcase
        @@command_counts_mutex.synchronize do
          @@command_counts.update(normalized_command) { |count| count + 1_u64 }
        end
      end

      def self.command_counts : Hash(String, UInt64)
        @@command_counts_mutex.synchronize do
          @@command_counts.dup
        end
      end

      # Time a block execution and categorize by operation type
      def self.time_burst(&)
        measure(@@burst_times, 100, MAX_BURST_TIME, "burst") { yield }
      end

      def self.time_message_processing(&)
        measure(@@message_processing_times, 1000, MAX_MESSAGE_TIME, "message processing") { yield }
      end

      def self.time_netsplit(&)
        measure(@@netsplit_times, 50, MAX_NETSPLIT_TIME, "netsplit") { yield }
      end

      private def self.measure(times : Deque(Time::Span), limit : Int32, warning_threshold : Time::Span,
                               operation : String, &)
        start_time = Time.monotonic
        result = yield
        duration = Time.monotonic - start_time

        times << duration
        times.shift if times.size > limit

        if duration > warning_threshold
          Log.warn { "Slow #{operation} operation: #{duration}" }
        end

        result
      end

      # Get current metrics snapshot
      def self.snapshot
        {
          messages_processed: @@message_count.get,
          active_users:       Infrastructure::ServiceLocator.user_repository.size.to_u32,
          active_servers:     ServerHandler.servers.size.to_u32,
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
        @@channel_operations.set(0_u64)
        @@command_counts_mutex.synchronize do
          @@command_counts.clear
        end
        @@burst_times.clear
        @@message_processing_times.clear
        @@netsplit_times.clear
      end

      private def self.calculate_average(times : Deque(Time::Span)) : Time::Span
        return Time::Span.zero if times.empty?
        total = times.sum
        Time::Span.new(nanoseconds: (total.total_nanoseconds / times.size).to_i)
      end
    end
  end
end
