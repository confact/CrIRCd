require "../../spec_helper"

describe Circed::UserMode do
  # TODO: Write tests

  it "should be OK" do
    Circed::UserMode.new.should be_a(Circed::UserMode)
  end

  it "add a mode" do
    Circed::UserMode.new.add("o").should eq("o")
  end

  it "add a wrong mode" do
    expect_raises(Exception) { Circed::UserMode.new.add("a") }
  end

  it "remove a mode" do
    mode = Circed::UserMode.new
    mode.add("o")
    mode.remove("o").should eq("")
  end

  it "remove a wrong mode" do
    expect_raises(Exception) { Circed::UserMode.new.remove("a") }
  end

  it "check if a mode is set" do
    mode = Circed::UserMode.new
    mode.add("o")
    mode.has_mode?("o").should be_true
  end

  it "check if a wrong mode is set" do
    Circed::UserMode.new.has_mode?("a").should be_false
  end

  it "check if a mode is operator" do
    mode = Circed::UserMode.new
    mode.add("o")
    mode.is_operator?.should be_true
  end

  it "check if a mode is not operator" do
    Circed::UserMode.new.is_operator?.should be_false
  end

  it "check if a mode is voice" do
    mode = Circed::UserMode.new
    mode.add("v")
    mode.is_voiced?.should be_true
  end

  it "check if a mode is not voice" do
    Circed::UserMode.new.is_voiced?.should be_false
  end
end
