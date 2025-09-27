require "../../spec_helper"

describe Circed::Services::AccessLevel do
  describe "to_mode_char" do
    it "returns correct mode characters" do
      Circed::Services::AccessLevel::Voice.to_mode_char.should eq('v')
      Circed::Services::AccessLevel::HalfOp.to_mode_char.should eq('h')
      Circed::Services::AccessLevel::Operator.to_mode_char.should eq('o')
      Circed::Services::AccessLevel::Admin.to_mode_char.should eq('a')
      Circed::Services::AccessLevel::Founder.to_mode_char.should eq('q')
      Circed::Services::AccessLevel::None.to_mode_char.should eq(' ')
    end
  end

  describe "value comparison" do
    it "compares access levels correctly" do
      (Circed::Services::AccessLevel::Founder >= Circed::Services::AccessLevel::Admin).should be_true
      (Circed::Services::AccessLevel::Admin >= Circed::Services::AccessLevel::Operator).should be_true
      (Circed::Services::AccessLevel::Operator >= Circed::Services::AccessLevel::Voice).should be_true
      (Circed::Services::AccessLevel::Voice >= Circed::Services::AccessLevel::None).should be_true
    end
  end
end

describe Circed::Services::RegisteredChannel do
  it "initializes correctly" do
    access_list = [] of Circed::Services::ChannelAccess
    channel = Circed::Services::RegisteredChannel.new(
      1, "#test", "founder", Time.utc, "Test topic", "+nt", access_list.to_json, Time.utc
    )

    channel.channel_name.should eq("#test")
    channel.founder.should eq("founder")
    channel.topic.should eq("Test topic")
    channel.modes.should eq("+nt")
  end

  describe "#has_access?" do
    it "checks access levels correctly" do
      access_entry = Circed::Services::ChannelAccess.new(
        1, "#test", "operator", 3, "founder", Time.utc
      )
      access_list = [access_entry]

      channel = Circed::Services::RegisteredChannel.new(
        1, "#test", "founder", Time.utc, nil, "+nt", access_list.to_json, Time.utc
      )

      channel.has_access?("operator", Circed::Services::AccessLevel::Operator).should be_true
      channel.has_access?("operator", Circed::Services::AccessLevel::Admin).should be_false
      channel.has_access?("random", Circed::Services::AccessLevel::Voice).should be_false
    end
  end

  describe "#get_access_level" do
    it "returns correct access level" do
      access_entry = Circed::Services::ChannelAccess.new(
        1, "#test", "operator", 3, "founder", Time.utc
      )
      access_list = [access_entry]

      channel = Circed::Services::RegisteredChannel.new(
        1, "#test", "founder", Time.utc, nil, "+nt", access_list.to_json, Time.utc
      )

      channel.get_access_level("operator").should eq(Circed::Services::AccessLevel::Operator)
      channel.get_access_level("random").should eq(Circed::Services::AccessLevel::None)
    end
  end
end

describe Circed::Services::RegisteredUser do
  it "initializes correctly" do
    user = Circed::Services::RegisteredUser.new(
      1, "testuser", "hashed_password", "test@example.com",
      Time.utc, Time.utc, ["admin"].to_json
    )

    user.nickname.should eq("testuser")
    user.email.should eq("test@example.com")
    user.flags.should eq(["admin"])
  end

  describe "#has_flag?" do
    it "checks flags correctly" do
      user = Circed::Services::RegisteredUser.new(
        1, "testuser", "hashed_password", nil,
        Time.utc, Time.utc, ["admin", "vip"].to_json
      )

      user.has_flag?("admin").should be_true
      user.has_flag?("vip").should be_true
      user.has_flag?("banned").should be_false
    end
  end
end
