require "../../spec_helper"

describe Circed::OutboundBatch do
  it "drains available messages up to the count limit" do
    messages = Channel(String).new(2)
    messages.send("two")
    messages.send("three")

    Circed::OutboundBatch.build(messages, "one", 2, 100).should eq("onetwo")
    messages.receive.should eq("three")
  end

  it "does not consume another message after reaching the byte limit" do
    messages = Channel(String).new(1)
    messages.send("two")

    Circed::OutboundBatch.build(messages, "one", 10, 3).should eq("one")
    messages.receive.should eq("two")
  end

  it "drains buffered messages from a closed channel" do
    messages = Channel(String).new(1)
    messages.send("two")
    messages.close

    Circed::OutboundBatch.build(messages, "one", 10, 100).should eq("onetwo")
  end
end
