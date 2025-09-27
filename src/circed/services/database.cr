require "sqlite3"

module Circed::Services
  # Database management for IRC services
  class Database
    @@database : DB::Database?

    def self.setup(db_path : String = "services.db")
      @@database = DB.open("sqlite3://#{db_path}")
      create_tables
    end

    def self.db
      @@database || raise "Database not initialized. Call Database.setup first."
    end

    private def self.create_tables
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS registered_channels (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          channel_name TEXT UNIQUE NOT NULL,
          founder TEXT NOT NULL,
          registered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          topic TEXT,
          modes TEXT DEFAULT '+nt',
          access_list TEXT DEFAULT '[]',
          last_used DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS channel_access (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          channel_name TEXT NOT NULL,
          nickname TEXT NOT NULL,
          access_level INTEGER NOT NULL,
          added_by TEXT NOT NULL,
          added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(channel_name, nickname)
        )
      SQL

      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS registered_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nickname TEXT UNIQUE NOT NULL,
          password_hash TEXT NOT NULL,
          email TEXT,
          registered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
          flags TEXT DEFAULT '[]'
        )
      SQL

      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS user_aliases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nickname TEXT NOT NULL,
          alias TEXT NOT NULL,
          added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(alias)
        )
      SQL
    end
  end
end
