require "../spec_helper"

describe "Server Connection Detection" do
  describe "connection type detection logic" do
    it "should identify server commands correctly in buffer" do
      buffer = ["PASS testlink123", "SERVER test.server.com 1 :Test IRC Server"]

      # This demonstrates the bug - the current logic won't work
      has_pass = buffer.includes?("PASS")
      has_server = buffer.includes?("SERVER")

      # These should be false with current buggy logic
      has_pass.should be_false
      has_server.should be_false

      # The correct logic should check if any line starts with the command
      has_pass_correct = buffer.any?(&.starts_with?("PASS"))
      has_server_correct = buffer.any?(&.starts_with?("SERVER"))

      # These should be true with correct logic
      has_pass_correct.should be_true
      has_server_correct.should be_true
    end

    it "should identify client commands correctly in buffer" do
      buffer = ["NICK testuser", "USER test test localhost :Test User"]

      # Current buggy logic
      has_nick = buffer.includes?("NICK")
      has_user = buffer.includes?("USER")

      # These should be false with current buggy logic
      has_nick.should be_false
      has_user.should be_false

      # Correct logic
      has_nick_correct = buffer.any?(&.starts_with?("NICK"))
      has_user_correct = buffer.any?(&.starts_with?("USER"))

      # These should be true with correct logic
      has_nick_correct.should be_true
      has_user_correct.should be_true
    end
  end

  describe "DummySocket" do
    it "should simulate IRC data correctly" do
      socket = DummySocket.new
      socket.add_receive_data("PASS testlink123")
      socket.add_receive_data("SERVER test.server.com 1 :Test IRC Server")

      line1 = socket.gets
      line2 = socket.gets
      line3 = socket.gets

      line1.should eq("PASS testlink123")
      line2.should eq("SERVER test.server.com 1 :Test IRC Server")
      line3.should be_nil
    end
  end
end
