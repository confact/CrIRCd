require "../../spec_helper"

describe Circed::Utils::IrcUtils do
  it "accepts RFC channel prefixes" do
    ["#chan", "&chan", "+chan", "!ABCDEchan"].each do |channel_name|
      Circed::Utils::IrcUtils.valid_channel_name?(channel_name).should be_true
    end
  end

  it "rejects invalid channel separators and control characters" do
    ["chan", "#bad name", "#bad,name", "#bad\a"].each do |channel_name|
      Circed::Utils::IrcUtils.valid_channel_name?(channel_name).should be_false
    end
  end

  it "accepts RFC nickname specials and enforces the channel length limit" do
    Circed::Utils::IrcUtils.valid_nickname?("^Nick").should be_true
    Circed::Utils::IrcUtils.valid_channel_name?("##{"a" * 49}").should be_true
    Circed::Utils::IrcUtils.valid_channel_name?("##{"a" * 50}").should be_false
  end

  it "builds IRC trailing params" do
    Circed::Utils::IrcUtils.trailing_param([":hello", "world"], 0).should eq("hello world")
    Circed::Utils::IrcUtils.trailing_param(["nick", ":because", "spam"], 1).should eq("because spam")
    Circed::Utils::IrcUtils.trailing_param(["nick"], 1, "No reason").should eq("No reason")
  end

  it "iterates comma list params without empty items" do
    items = [] of String
    Circed::Utils::IrcUtils.each_list_param(",#one,,#two,") do |item|
      items << item
    end

    items.should eq(["#one", "#two"])
  end

  it "formats IRC mode sets" do
    Circed::Utils::IrcUtils.mode_string(Set(Char).new).should eq("+")
    Circed::Utils::IrcUtils.mode_string(Set{'i', 'w'}).should eq("+iw")
  end

  it "parses IRC mode sets" do
    Circed::Utils::IrcUtils.mode_set("+iw-o").should eq(Set{'i', 'w', 'o'})
  end
end
