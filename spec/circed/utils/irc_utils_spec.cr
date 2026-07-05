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
end
