require "../../spec_helper"

describe Circed::Channel do
  # TODO: Write tests

  it "should be able to create a new channel" do
    channel = Circed::Channel.new("")
    channel.should be_a(Circed::Channel)
  end

  it "should be able to create a new channel with a name" do
    channel = Circed::Channel.new("test")
    channel.should be_a(Circed::Channel)
    channel.name.should eq("#test")
  end

  it "should be able to create a new channel with a name and empty users" do
    channel = Circed::Channel.new("test")
    channel.should be_a(Circed::Channel)
    channel.name.should eq("#test")
    channel.channel_empty?.should be_true
    channel.irc_name.should eq(":#test")
  end

  it "should be able to add users to a channel" do
    channel = Circed::Channel.new("test")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    channel.channel_empty?.should be_false
    channel.user_in_channel?(client).should be_true
  end

  it "should be able to remove users from a channel" do
    channel = Circed::Channel.new("test")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    channel.channel_empty?.should be_false
    channel.user_in_channel?(client).should be_true
    channel.remove_client(client)
    channel.channel_empty?.should be_true
    channel.user_in_channel?(client).should be_false
  end

  it "should be able to change mode" do
    channel = Circed::Channel.new("#test")
    channel.modes.should eq({} of String => String)
    client = Circed::Client.new(nil)
    channel.add_client(client)
    channel.change_channel_mode(client, "+s")
    channel.modes.should eq({"s" => nil})
  end

  it "should not be able to change mode if not part of channel" do
    channel = Circed::Channel.new("test")
    channel.modes.should eq({} of String => String)
    client = Circed::Client.new(nil)
    channel.change_channel_mode(client, "+s")
    channel.modes.should eq({} of String => String)
  end

  it "should be able to change topic if part of channel" do
    client = Circed::Client.new(nil)
    Circed::ChannelHandler.add_user_to_channel("#test", client)
    channel = Circed::ChannelHandler.get_channel("#test")
    channel.try(&.topic).should eq("")
    Circed::Actions::Topic.call(client, ["#test", "test"])
    channel.try(&.topic).should eq("test")
    channel.try(&.topic_setter).should be_a(Circed::ChannelUser)
  end

  it "should not be able to change topic if not part of channel" do
    channel = Circed::Channel.new("#test")
    channel.topic.should eq("")
    client = Circed::Client.new(nil)
    Circed::Actions::Topic.call(client, [channel.name, "test"])
    channel.topic.should eq("")
  end

  it "should not be able to change topic if not operator" do
    channel = Circed::Channel.new("#test")
    channel.topic.should eq("")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    client2 = Circed::Client.new(nil)
    channel.add_client(client2)
    Circed::Actions::Topic.call(client2, [channel.name, "test"])
    channel.topic.should eq("")
  end
end
