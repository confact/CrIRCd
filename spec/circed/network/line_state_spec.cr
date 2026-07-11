require "../../spec_helper"

describe Circed::Network::LineState do
  before_each do
    Circed::Network::LineState.clear
  end

  after_each do
    Circed::Network::LineState.clear
  end

  it "normalizes K-line and G-line user host masks" do
    Circed::Network::LineState.normalize_mask("KLINE", "bad.example").should eq("*!*@bad.example")
    Circed::Network::LineState.normalize_mask("GLINE", "*@bad.example").should eq("*!*@bad.example")
    Circed::Network::LineState.normalize_mask("GLINE", "nick!*@Bad.Example").should eq("nick!*@bad.example")
    Circed::Network::LineState.normalize_mask("zline", "user@203.0.113.1").should eq("203.0.113.1")
  end

  it "uses one stable key format for lines" do
    line = Circed::Domain::LineBan.new("gline", "*!*@bad.example", "spam", "oper")

    line.key.should eq(Circed::Domain::LineBan.key("GLINE", "*!*@bad.example"))
    Circed::Domain::LineBan.key("gline", "*!*@bad.example").should eq("GLINE:*!*@bad.example")
  end

  it "matches K-lines and G-lines against hostmasks" do
    context = Circed::Domain::BanMatchContext.new(
      "Alice",
      "alice",
      "bad.example",
      "192.0.2.10",
      "Alice",
      "Alice!alice@bad.example",
      [] of String
    )

    Circed::Network::LineState.add("KLINE", "*@bad.example", "spam", "oper")

    Circed::Network::LineState.matching(context).try(&.type).should eq("KLINE")
  end

  it "matches Z-lines against exact IPs, wildcards, and IPv4 CIDR masks" do
    context = Circed::Domain::BanMatchContext.new(
      "Alice",
      "alice",
      "host.example",
      "192.0.2.42",
      "Alice",
      "Alice!alice@host.example",
      [] of String
    )

    Circed::Network::LineState.add("ZLINE", "192.0.2.0/24", "abuse", "oper")
    Circed::Network::LineState.matching(context).try(&.type).should eq("ZLINE")

    Circed::Network::LineState.clear
    Circed::Network::LineState.add("ZLINE", "198.51.100.*", "abuse", "oper")
    Circed::Network::LineState.matching(context).should be_nil
  end

  it "ignores malformed IPv4 CIDR masks" do
    context = Circed::Domain::BanMatchContext.new(
      "Alice",
      "alice",
      "host.example",
      "192.0.2.42",
      "Alice",
      "Alice!alice@host.example",
      [] of String
    )

    Circed::Network::LineState.add("ZLINE", "192.0.2.999/24", "abuse", "oper")
    Circed::Network::LineState.add("ZLINE", "192.0.2.0/33", "abuse", "oper")

    Circed::Network::LineState.matching(context).should be_nil
  end

  it "expires temporary lines" do
    context = Circed::Domain::BanMatchContext.new(
      "Alice",
      "alice",
      "bad.example",
      "192.0.2.10",
      "Alice",
      "Alice!alice@bad.example",
      [] of String
    )

    Circed::Network::LineState.add("GLINE", "*@bad.example", "spam", "oper", -1.second)

    Circed::Network::LineState.matching(context).should be_nil
  end

  it "ignores blank masks when removing lines" do
    Circed::Network::LineState.add("GLINE", "*@bad.example", "spam", "oper")

    Circed::Network::LineState.remove("GLINE", "   ").should be_false
  end

  it "persists active lines to the configured database" do
    path = File.tempname("circed-lines", ".yml")
    empty_path = File.tempname("circed-empty-lines", ".yml")
    File.delete(empty_path) if File.exists?(empty_path)
    Circed::Network::LineState.configure_persistence(path, enabled: true)
    Circed::Network::LineState.add("GLINE", "*@bad.example", "Spam", "oper")

    Circed::Network::LineState.configure_persistence(empty_path, enabled: true)
    Circed::Network::LineState.configure_persistence(path, enabled: true)

    context = Circed::Domain::BanMatchContext.new(
      "Alice",
      "alice",
      "bad.example",
      "192.0.2.10",
      "Alice",
      "Alice!alice@bad.example",
      [] of String
    )
    Circed::Network::LineState.matching(context).try(&.type).should eq("GLINE")
  ensure
    File.delete(path) if path && File.exists?(path)
    File.delete(empty_path) if empty_path && File.exists?(empty_path)
    Circed::Network::LineState.configure_persistence("data/lines.yml", enabled: false)
  end
end
