require "../../spec_helper"

describe Circed::Services::Database do
  before_each do
    # Use in-memory database for testing
    File.delete("test_services.db") if File.exists?("test_services.db")
    Circed::Services::Database.setup("test_services.db")
  end

  after_each do
    # Clean up test database
    File.delete("test_services.db") if File.exists?("test_services.db")
  end

  describe "setup" do
    it "creates database and tables" do
      # Database should be accessible
      db = Circed::Services::Database.db
      db.should_not be_nil

      # Tables should exist
      result = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('registered_channels', 'channel_access', 'registered_users', 'user_aliases')")
      result.should eq(4)
    end
  end

  describe "registered_channels table" do
    it "allows inserting and querying channels" do
      db = Circed::Services::Database.db

      # Insert a channel
      db.exec(
        "INSERT INTO registered_channels (channel_name, founder) VALUES (?, ?)",
        "#test", "testuser"
      )

      # Query the channel
      result = db.query_one(
        "SELECT channel_name, founder FROM registered_channels WHERE channel_name = ?",
        "#test"
      ) do |result_set|
        {result_set.read(String), result_set.read(String)}
      end

      result[0].should eq("#test")
      result[1].should eq("testuser")
    end
  end

  describe "channel_access table" do
    it "allows managing channel access" do
      db = Circed::Services::Database.db

      # Insert access entry
      db.exec(
        "INSERT INTO channel_access (channel_name, nickname, access_level, added_by) VALUES (?, ?, ?, ?)",
        "#test", "operator", 3, "founder"
      )

      # Query access
      result = db.query_one(
        "SELECT nickname, access_level FROM channel_access WHERE channel_name = ?",
        "#test"
      ) do |result_set|
        {result_set.read(String), result_set.read(Int32)}
      end

      result[0].should eq("operator")
      result[1].should eq(3)
    end
  end

  describe "registered_users table" do
    it "allows user registration" do
      db = Circed::Services::Database.db

      # Insert a user
      db.exec(
        "INSERT INTO registered_users (nickname, password_hash, email) VALUES (?, ?, ?)",
        "testuser", "hashed_password", "test@example.com"
      )

      # Query the user
      result = db.query_one(
        "SELECT nickname, email FROM registered_users WHERE nickname = ?",
        "testuser"
      ) do |result_set|
        {result_set.read(String), result_set.read(String?)}
      end

      result[0].should eq("testuser")
      result[1].should eq("test@example.com")
    end
  end

  describe "user_aliases table" do
    it "allows managing user aliases" do
      db = Circed::Services::Database.db

      # Insert an alias
      db.exec(
        "INSERT INTO user_aliases (nickname, alias) VALUES (?, ?)",
        "mainuser", "altuser"
      )

      # Query the alias
      result = db.query_one(
        "SELECT nickname, alias FROM user_aliases WHERE alias = ?",
        "altuser"
      ) do |result_set|
        {result_set.read(String), result_set.read(String)}
      end

      result[0].should eq("mainuser")
      result[1].should eq("altuser")
    end
  end
end
