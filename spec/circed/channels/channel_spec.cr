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
    channel = Circed::Channel.new("test")
    channel.mode.should eq("")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    channel.change_channel_mode(client, "+o")
    channel.mode.should eq("o")
  end

  it "should not be able to change mode if not part of channel" do
    channel = Circed::Channel.new("test")
    channel.mode.should eq("")
    client = Circed::Client.new(nil)
    channel.change_channel_mode(client, "+o")
    channel.mode.should eq("")
  end

  it "should be able to change topic if part of channel" do
    channel = Circed::Channel.new("test")
    channel.topic.should eq("")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    channel.set_topic(client, "test")
    channel.topic.should eq("test")
    channel.topic_setter.should be_a(Circed::ChannelUser)
  end

  it "should not be able to change topic if not part of channel" do
    channel = Circed::Channel.new("test")
    channel.topic.should eq("")
    client = Circed::Client.new(nil)
    channel.set_topic(client, "test")
    channel.topic.should eq("")
  end

  it "should not be able to change topic if not operator" do
    channel = Circed::Channel.new("test")
    channel.topic.should eq("")
    client = Circed::Client.new(nil)
    channel.add_client(client)
    client2 = Circed::Client.new(nil)
    channel.add_client(client2)
    channel.set_topic(client2, "test")
    channel.topic.should eq("")
  end
end
