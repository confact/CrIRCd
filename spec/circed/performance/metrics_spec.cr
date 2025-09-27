require "../../spec_helper"

describe Circed::Performance::Metrics do
  before_each do
    Circed::Performance::Metrics.reset
  end

  describe "message counting" do
    it "tracks message increments atomically" do
      Circed::Performance::Metrics.increment_messages(5_u64)
      Circed::Performance::Metrics.increment_messages(3_u64)

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:messages_processed].should eq(8_u64)
    end
  end

  describe "timing measurements" do
    it "measures burst performance" do
      result = Circed::Performance::Metrics.time_burst do
        sleep 10.milliseconds
        "test_result"
      end

      result.should eq("test_result")
      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:avg_burst_time].should be > Time::Span.zero
    end

    it "measures message processing performance" do
      result = Circed::Performance::Metrics.time_message_processing do
        sleep 1.millisecond
        42
      end

      result.should eq(42)
      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:avg_message_time].should be > Time::Span.zero
    end

    it "warns about slow operations" do
      # This would log a warning in real usage
      Circed::Performance::Metrics.time_burst do
        sleep 6.seconds # Exceeds MAX_BURST_TIME
        "slow_operation"
      end

      Circed::Performance::Metrics.performance_warning?.should be_true
    end
  end

  describe "connection tracking" do
    it "tracks user connections" do
      Circed::Performance::Metrics.reset # Ensure clean state
      Circed::Performance::Metrics.increment_user_connections
      Circed::Performance::Metrics.increment_user_connections
      Circed::Performance::Metrics.decrement_user_connections

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:active_users].should eq(1_u32)
    end

    it "tracks server connections" do
      Circed::Performance::Metrics.reset # Ensure clean state
      Circed::Performance::Metrics.increment_server_connections
      Circed::Performance::Metrics.increment_server_connections

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:active_servers].should eq(2_u32)
    end
  end

  describe "performance analysis" do
    it "provides optimization suggestions" do
      # Simulate high message processing time
      50.times do
        Circed::Performance::Metrics.time_message_processing do
          sleep 25.milliseconds # Above normal threshold
        end
      end

      suggestions = Circed::Performance::Metrics.optimization_suggestions
      suggestions.any? { |suggestion| suggestion.includes?("message") && suggestion.includes?("batch") }.should be_true
    end

    it "detects performance warnings" do
      # Create slow burst
      Circed::Performance::Metrics.time_burst { sleep 6.seconds }

      Circed::Performance::Metrics.performance_warning?.should be_true
    end
  end

  describe "metrics reset" do
    it "resets all counters and measurements" do
      Circed::Performance::Metrics.increment_messages(10_u64)
      Circed::Performance::Metrics.increment_user_connections
      Circed::Performance::Metrics.time_burst { sleep 1.millisecond }

      Circed::Performance::Metrics.reset

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:messages_processed].should eq(0_u64)
      snapshot[:avg_burst_time].should eq(Time::Span.zero)
    end
  end
end
