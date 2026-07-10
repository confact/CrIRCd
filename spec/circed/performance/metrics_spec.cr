require "../../spec_helper"

describe Circed::Performance::Metrics do
  before_each do
    clear_repositories
    Circed::Performance::Metrics.reset
  end

  after_each { clear_repositories }

  describe "message counting" do
    it "tracks message increments atomically" do
      Circed::Performance::Metrics.increment_messages(5_u64)
      Circed::Performance::Metrics.increment_messages(3_u64)

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:messages_processed].should eq(8_u64)
    end

    it "tracks command counts by normalized command name" do
      Circed::Performance::Metrics.increment_command("privmsg")
      Circed::Performance::Metrics.increment_command("PRIVMSG")
      Circed::Performance::Metrics.increment_command("join")

      counts = Circed::Performance::Metrics.command_counts
      counts["PRIVMSG"].should eq(2_u64)
      counts["JOIN"].should eq(1_u64)
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
  end

  describe "connection tracking" do
    it "reports users from the owning repository" do
      create_test_client("Alice")

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:active_users].should eq(1_u32)
    end
  end

  describe "metrics reset" do
    it "resets all counters and measurements" do
      Circed::Performance::Metrics.increment_messages(10_u64)
      Circed::Performance::Metrics.time_burst { sleep 1.millisecond }

      Circed::Performance::Metrics.reset

      snapshot = Circed::Performance::Metrics.snapshot
      snapshot[:messages_processed].should eq(0_u64)
      snapshot[:avg_burst_time].should eq(Time::Span.zero)
      Circed::Performance::Metrics.command_counts.should be_empty
    end
  end
end
