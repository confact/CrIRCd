require "../../spec_helper"

describe Circed::Network::FastMessageParser do
  describe "message parsing" do
    it "parses basic IRC message" do
      message = Circed::Network::FastMessageParser.parse("PRIVMSG #channel :Hello world")

      message.should_not be_nil
      message.try(&.command).should eq("PRIVMSG")
      message.try(&.params.size).should eq(2)
      message.try(&.params[0]).should eq("#channel")
      message.try(&.params[1]).should eq(":Hello world")
    end

    it "parses message with prefix" do
      message = Circed::Network::FastMessageParser.parse(":nick!user@host PRIVMSG #channel :Hello")

      message.should_not be_nil
      message.try(&.prefix).should eq("nick!user@host")
      message.try(&.command).should eq("PRIVMSG")
      message.try(&.source_nick).should eq("nick")
      message.try(&.source_user).should eq("user")
      message.try(&.source_host).should eq("host")
    end

    it "parses server message without user@host" do
      message = Circed::Network::FastMessageParser.parse(":server.irc SQUIT target.irc :Quit message")

      message.should_not be_nil
      message.try(&.prefix).should eq("server.irc")
      message.try(&.server_message?).should be_true
      message.try(&.source_nick).should be_nil
    end

    it "handles trailing parameter correctly" do
      message = Circed::Network::FastMessageParser.parse("PRIVMSG #channel :This is a long message")

      message.should_not be_nil
      message.try(&.trailing_param).should eq("This is a long message")
    end

    it "handles multiple parameters" do
      message = Circed::Network::FastMessageParser.parse("NICK oldnick newnick :New nickname")

      message.should_not be_nil
      message.try(&.params.size).should eq(3)
      message.try(&.params).should eq(["oldnick", "newnick", ":New nickname"])
    end

    it "handles empty messages gracefully" do
      message = Circed::Network::FastMessageParser.parse("")
      message.should be_nil

      message = Circed::Network::FastMessageParser.parse("   ")
      message.should be_nil
    end

    it "handles malformed messages gracefully" do
      message = Circed::Network::FastMessageParser.parse(":")
      message.should be_nil

      message = Circed::Network::FastMessageParser.parse(":prefix")
      message.should be_nil
    end
  end

  describe "command-only parsing" do
    it "extracts command quickly" do
      command = Circed::Network::FastMessageParser.parse_command_only("PRIVMSG #channel :Hello")
      command.should eq("PRIVMSG")

      command = Circed::Network::FastMessageParser.parse_command_only(":nick!user@host JOIN #channel")
      command.should eq("JOIN")
    end

    it "handles empty input gracefully" do
      command = Circed::Network::FastMessageParser.parse_command_only("")
      command.should be_nil
    end
  end

  describe "priority detection" do
    it "identifies high-priority commands" do
      Circed::Network::FastMessageParser.high_priority?("SQUIT").should be_true
      Circed::Network::FastMessageParser.high_priority?("KILL").should be_true
      Circed::Network::FastMessageParser.high_priority?("ERROR").should be_true
      Circed::Network::FastMessageParser.high_priority?("PING").should be_true
      Circed::Network::FastMessageParser.high_priority?("PONG").should be_true

      Circed::Network::FastMessageParser.high_priority?("PRIVMSG").should be_false
      Circed::Network::FastMessageParser.high_priority?("JOIN").should be_false
    end
  end

  describe "format validation" do
    it "validates message format" do
      Circed::Network::FastMessageParser.valid_format?("PRIVMSG #channel :Hello").should be_true
      Circed::Network::FastMessageParser.valid_format?(":nick!user@host JOIN #channel").should be_true

      # Invalid formats
      Circed::Network::FastMessageParser.valid_format?("").should be_false
      Circed::Network::FastMessageParser.valid_format?(":" + "a" * 600).should be_false  # Too long
      Circed::Network::FastMessageParser.valid_format?(":prefix").should be_false  # No command
      Circed::Network::FastMessageParser.valid_format?("PRIV@MSG").should be_false  # Invalid command chars
    end
  end

  describe "batch parsing" do
    it "parses multiple messages efficiently" do
      lines = [
        "PRIVMSG #channel :Hello",
        ":nick!user@host JOIN #channel",
        "SQUIT server.irc :Quit message"
      ]

      messages = Circed::Network::FastMessageParser.parse_batch(lines)
      messages.size.should eq(3)
      messages[0].command.should eq("PRIVMSG")
      messages[1].command.should eq("JOIN")
      messages[2].command.should eq("SQUIT")
    end

    it "skips invalid messages in batch" do
      lines = [
        "PRIVMSG #channel :Hello",
        "",  # Invalid
        ":nick!user@host JOIN #channel",
        ":",  # Invalid
        "SQUIT server.irc :Quit message"
      ]

      messages = Circed::Network::FastMessageParser.parse_batch(lines)
      messages.size.should eq(3)  # Only valid messages
    end
  end
end