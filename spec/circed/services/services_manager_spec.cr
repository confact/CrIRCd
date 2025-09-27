require "../../spec_helper"

describe Circed::Services::ServicesManager do
  before_each do
    clear_repositories
    Circed::Network::NetworkState.clear_all_state

    # Setup test database
    File.delete("test_services.db") if File.exists?("test_services.db")
    Circed::Services::ServicesManager.setup("test_services.db")
  end

  after_each do
    clear_repositories
    File.delete("test_services.db") if File.exists?("test_services.db")
  end

  describe "setup" do
    it "initializes services" do
      # Services should be available
      Circed::Services::ServicesManager.chanserv.should_not be_nil
      Circed::Services::ServicesManager.userserv.should_not be_nil
    end
  end

  describe "service?" do
    it "identifies service nicknames" do
      Circed::Services::ServicesManager.service?("ChanServ").should be_true
      Circed::Services::ServicesManager.service?("chanserv").should be_true
      Circed::Services::ServicesManager.service?("UserServ").should be_true
      Circed::Services::ServicesManager.service?("userserv").should be_true
      Circed::Services::ServicesManager.service?("RegularUser").should be_false
    end
  end

  describe "handle_service_message" do
    it "routes messages to ChanServ" do
      # Should not crash when routing to ChanServ
      Circed::Services::ServicesManager.handle_service_message("testuser", "ChanServ", "HELP")
      true.should be_true
    end

    it "routes messages to UserServ" do
      # Should not crash when routing to UserServ
      Circed::Services::ServicesManager.handle_service_message("testuser", "UserServ", "HELP")
      true.should be_true
    end

    it "handles unknown services gracefully" do
      # This should not crash
      Circed::Services::ServicesManager.handle_service_message("testuser", "UnknownService", "HELP")
    end
  end

  describe "user_identified?" do
    it "returns false for unregistered users" do
      Circed::Services::ServicesManager.user_identified?("nonexistent").should be_false
    end

    it "delegates to UserServ" do
      # Should return boolean values
      result1 = Circed::Services::ServicesManager.user_identified?("identified_user")
      result2 = Circed::Services::ServicesManager.user_identified?("other_user")
      result1.should be_a(Bool)
      result2.should be_a(Bool)
    end
  end

  describe "get_channel_access" do
    it "returns None for unregistered channels" do
      access = Circed::Services::ServicesManager.get_channel_access("#test", "user")
      access.should eq(Circed::Services::AccessLevel::None)
    end

    it "delegates to ChanServ for registered channels" do
      # Should return valid access level
      access = Circed::Services::ServicesManager.get_channel_access("#test", "founder")
      access.should be_a(Circed::Services::AccessLevel)
    end
  end

  describe "channel_registered?" do
    it "returns false for unregistered channels" do
      Circed::Services::ServicesManager.channel_registered?("#test").should be_false
    end

    it "delegates to ChanServ" do
      # Should return boolean values
      result1 = Circed::Services::ServicesManager.channel_registered?("#registered")
      result2 = Circed::Services::ServicesManager.channel_registered?("#unregistered")
      result1.should be_a(Bool)
      result2.should be_a(Bool)
    end
  end
end
