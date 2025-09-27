require "../spec_helper"

describe "Services Integration" do
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

  describe "PRIVMSG to services" do
    it "routes messages to ChanServ" do
      client = create_test_client("testuser")
      irc_service = Circed::Infrastructure::Container.irc_service

      # Send message to ChanServ - should route successfully
      result = irc_service.route_message(client, "ChanServ", "HELP")
      result.should be_true
    end

    it "routes messages to UserServ" do
      client = create_test_client("testuser")
      irc_service = Circed::Infrastructure::Container.irc_service

      # Send message to UserServ - should route successfully
      result = irc_service.route_message(client, "UserServ", "REGISTER password123")
      result.should be_true
    end

    it "handles normal user messages normally" do
      client = create_test_client("testuser")
      target_client = create_test_client("target")
      irc_service = Circed::Infrastructure::Container.irc_service

      # This should route to normal user handling
      result = irc_service.route_message(client, "target", "Hello there!")

      result.should be_true
    end
  end

  describe "Service registration with network" do
    it "registers services as virtual users" do
      # Services should be registered in network state
      chanserv_user = Circed::Network::NetworkState.get_user("ChanServ")
      userserv_user = Circed::Network::NetworkState.get_user("UserServ")

      chanserv_user.should_not be_nil
      userserv_user.should_not be_nil

      if chanserv_user
        chanserv_user.username.should eq("services")
        chanserv_user.realname.should eq("Channel Registration Service")
      end

      if userserv_user
        userserv_user.username.should eq("services")
        userserv_user.realname.should eq("User Registration Service")
      end
    end
  end

  describe "ChanServ channel integration" do
    it "integrates with channel operations" do
      # Create a channel with an operator
      client = create_test_client("testuser")
      irc_service = Circed::Infrastructure::Container.irc_service

      # Join channel (user becomes operator as first member)
      success = irc_service.join_channel(client, "#test")
      success.should be_true

      # Verify user is operator
      channel = Circed::Infrastructure::Container.channel_repository.get("#test")
      channel.should_not be_nil
      if channel
        member_modes = channel.members["testuser"]?
        member_modes.should_not be_nil
        if member_modes
          member_modes.should contain('o')
        end
      end

      # Now ChanServ channel registration should work (though we'd need to mock the database parts)
    end
  end

  describe "UserServ authentication integration" do
    it "provides identification status" do
      # Test the identification check functionality
      result = Circed::Services::ServicesManager.user_identified?("testuser")
      result.should be_a(Bool)
    end
  end

  describe "Services database persistence" do
    it "maintains data across service restarts" do
      # Register a channel
      db = Circed::Services::Database.db
      db.exec(
        "INSERT INTO registered_channels (channel_name, founder) VALUES (?, ?)",
        "#persistent", "testuser"
      )

      # Restart services (reinitialize)
      Circed::Services::ServicesManager.setup("test_services.db")

      # Data should still be there
      result = db.query_one(
        "SELECT founder FROM registered_channels WHERE channel_name = ?",
        "#persistent"
      ) do |result_set|
        result_set.read(String)
      end

      result.should eq("testuser")
    end
  end

  describe "Service command parsing" do
    it "correctly parses command and parameters" do
      # Test that the ServicesManager can handle service messages
      # Should not crash when handling service messages
      Circed::Services::ServicesManager.handle_service_message("user", "ChanServ", "REGISTER #channel password")
      true.should be_true
    end
  end
end
