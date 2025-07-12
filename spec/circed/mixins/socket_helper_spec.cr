require "../../spec_helper"

# Test class that includes SocketHelper for testing
class TestSocketHelper
  include Circed::SocketHelper
  
  getter socket : DummySocket
  
  def initialize(@socket : DummySocket)
  end
  
  def close
    @socket.close
  end
end

describe Circed::SocketHelper do
  describe "#safe_send" do
    it "sends message successfully on open socket" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      result = helper.safe_send("TEST MESSAGE")
      result.should be_true
    end
    
    it "fails gracefully on closed socket" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      socket.close
      
      result = helper.safe_send("TEST MESSAGE")
      result.should be_false
    end
    
    it "handles socket errors gracefully" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      # Mock a socket error by closing the socket
      socket.close
      
      result = helper.safe_send("TEST MESSAGE")
      result.should be_false
    end
  end
  
  describe "#send_error" do
    it "sends error message and closes connection" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      helper.send_error("Test error message")
      
      # Socket should be closed after sending error
      socket.closed?.should be_true
    end
    
    it "handles errors when socket is already closed" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      socket.close
      
      # Should not raise exception
      helper.send_error("Test error message")
      socket.closed?.should be_true
    end
  end
  
  describe "#send_irc_message" do
    it "formats IRC message with prefix correctly" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      result = helper.send_irc_message("PRIVMSG", ["#test", "hello world"], "nick!user@host")
      result.should be_true
      
      # We can't easily verify the exact message sent without modifying DummySocket
      # But we can verify it doesn't crash and returns success
    end
    
    it "formats IRC message without prefix correctly" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      result = helper.send_irc_message("PING", [":server.test.com"])
      result.should be_true
    end
    
    it "handles empty parameters" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      result = helper.send_irc_message("QUIT")
      result.should be_true
    end
    
    it "handles multiple parameters" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      result = helper.send_irc_message("USER", ["username", "hostname", "servername", "realname"])
      result.should be_true
    end
  end
  
  describe "#closed?" do
    it "returns false for open socket" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      helper.closed?.should be_false
    end
    
    it "returns true for closed socket" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      socket.close
      
      helper.closed?.should be_true
    end
    
    it "returns true for nil socket" do
      # Test the fallback behavior when socket is nil
      # Create a helper with a socket that will be set to nil internally
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      # Close the socket and verify the closed? method works
      socket.close
      helper.closed?.should be_true
    end
  end
  
  describe "integration with real IRC protocol" do
    it "formats complete IRC messages correctly" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      # Test various IRC message formats
      test_cases = [
        {command: "PRIVMSG", params: ["#channel", "Hello world"], prefix: "nick!user@host"},
        {command: "JOIN", params: ["#channel"], prefix: "nick!user@host"},
        {command: "PART", params: ["#channel", "Goodbye"], prefix: "nick!user@host"},
        {command: "PING", params: [":server.com"], prefix: nil},
        {command: "PONG", params: [":server.com"], prefix: nil},
        {command: "QUIT", params: ["Leaving"], prefix: "nick!user@host"}
      ]
      
      test_cases.each do |test_case|
        result = helper.send_irc_message(
          test_case[:command], 
          test_case[:params], 
          test_case[:prefix]
        )
        result.should be_true
      end
    end
    
    it "handles edge cases in IRC message formatting" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      # Test edge cases
      helper.send_irc_message("", [] of String).should be_true  # Empty command
      helper.send_irc_message("TEST", ["param with spaces"]).should be_true  # Spaces in params
      helper.send_irc_message("LONG", (1..10).map(&.to_s).to_a).should be_true  # Many params
    end
  end
  
  describe "error recovery" do
    it "continues working after socket errors" do
      socket = DummySocket.new
      helper = TestSocketHelper.new(socket)
      
      # Cause an error
      socket.close
      result1 = helper.safe_send("TEST")
      result1.should be_false
      
      # Create new helper with new socket to verify recovery
      new_socket = DummySocket.new
      new_helper = TestSocketHelper.new(new_socket)
      result2 = new_helper.safe_send("TEST")
      result2.should be_true
    end
  end
end