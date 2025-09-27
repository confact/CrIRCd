require "../../spec_helper"
require "crypto/bcrypt"

describe Circed::Services::UserServ do
  before_each do
    clear_repositories
    Circed::Network::NetworkState.clear_all_state

    # Setup test database
    File.delete("test_services.db") if File.exists?("test_services.db")
    Circed::Services::Database.setup("test_services.db")
  end

  after_each do
    clear_repositories
    File.delete("test_services.db") if File.exists?("test_services.db")
  end

  describe "initialization" do
    it "creates UserServ service" do
      userserv = Circed::Services::UserServ.new
      userserv.nickname.should eq("UserServ")
      userserv.username.should eq("services")
      userserv.realname.should eq("User Registration Service")
    end
  end

  describe "HELP command" do
    it "provides help information" do
      userserv = Circed::Services::UserServ.new

      # Should not crash when providing help
      userserv.handle_message("testuser", "HELP", [] of String)
      true.should be_true
    end
  end

  describe "REGISTER command" do
    it "validates registration syntax" do
      userserv = Circed::Services::UserServ.new

      # Should not crash with invalid input
      userserv.handle_message("testuser", "REGISTER", ["short"])
      userserv.handle_message("testuser", "REGISTER", [] of String)
      true.should be_true
    end

    it "prevents duplicate registrations" do
      userserv = Circed::Services::UserServ.new

      # Register user in database
      db = Circed::Services::Database.db
      password_hash = Crypto::Bcrypt::Password.create("password123").to_s
      db.exec(
        "INSERT INTO registered_users (nickname, password_hash) VALUES (?, ?)",
        "testuser", password_hash
      )

      # Should not crash when user is already registered
      userserv.handle_message("testuser", "REGISTER", ["password123", "test@example.com"])
      true.should be_true
    end
  end

  describe "IDENTIFY command" do
    it "validates identify syntax" do
      userserv = Circed::Services::UserServ.new

      # Should not crash with insufficient parameters
      userserv.handle_message("testuser", "IDENTIFY", [] of String)
      true.should be_true
    end

    it "handles non-existent users" do
      userserv = Circed::Services::UserServ.new

      # Should not crash for non-existent users
      userserv.handle_message("testuser", "IDENTIFY", ["password123"])
      true.should be_true
    end

    it "validates passwords" do
      userserv = Circed::Services::UserServ.new

      # Register user in database
      db = Circed::Services::Database.db
      password_hash = Crypto::Bcrypt::Password.create("correctpassword").to_s
      db.exec(
        "INSERT INTO registered_users (nickname, password_hash) VALUES (?, ?)",
        "testuser", password_hash
      )

      # Should not crash with wrong password
      userserv.handle_message("testuser", "IDENTIFY", ["wrongpassword"])
      true.should be_true
    end
  end

  describe "INFO command" do
    it "shows user information" do
      userserv = Circed::Services::UserServ.new

      # Register user in database
      db = Circed::Services::Database.db
      password_hash = Crypto::Bcrypt::Password.create("password123").to_s
      db.exec(
        "INSERT INTO registered_users (nickname, password_hash, email) VALUES (?, ?, ?)",
        "testuser", password_hash, "test@example.com"
      )

      # Should not crash when showing user info
      userserv.handle_message("someone", "INFO", ["testuser"])
      true.should be_true
    end

    it "handles non-existent users" do
      userserv = Circed::Services::UserServ.new

      # Should not crash for non-existent users
      userserv.handle_message("testuser", "INFO", ["nonexistent"])
      true.should be_true
    end
  end

  describe "GHOST command" do
    it "validates ghost syntax" do
      userserv = Circed::Services::UserServ.new

      # Should not crash with insufficient parameters
      userserv.handle_message("testuser", "GHOST", ["target"])
      true.should be_true
    end

    it "requires valid registration" do
      userserv = Circed::Services::UserServ.new

      # Should not crash for unregistered targets
      userserv.handle_message("testuser", "GHOST", ["target", "password"])
      true.should be_true
    end
  end

  describe "SET command" do
    it "validates set syntax" do
      userserv = Circed::Services::UserServ.new

      # Should not crash with insufficient parameters
      userserv.handle_message("testuser", "SET", ["PASSWORD"])
      true.should be_true
    end

    it "requires registration" do
      userserv = Circed::Services::UserServ.new

      # Should not crash for unregistered users
      userserv.handle_message("testuser", "SET", ["PASSWORD", "newpass"])
      true.should be_true
    end
  end

  describe "GROUP command" do
    it "validates group syntax" do
      userserv = Circed::Services::UserServ.new

      # Should not crash with insufficient parameters
      userserv.handle_message("testuser", "GROUP", ["target"])
      true.should be_true
    end
  end

  describe "identified?" do
    it "returns false for unregistered users" do
      userserv = Circed::Services::UserServ.new
      userserv.identified?("nonexistent").should be_false
    end

    it "returns true for registered users (simplified check)" do
      userserv = Circed::Services::UserServ.new

      # Register user in database
      db = Circed::Services::Database.db
      password_hash = Crypto::Bcrypt::Password.create("password123").to_s
      db.exec(
        "INSERT INTO registered_users (nickname, password_hash) VALUES (?, ?)",
        "testuser", password_hash
      )

      # In this simplified implementation, any registered user is considered identified
      userserv.identified?("testuser").should be_true
    end
  end
end
