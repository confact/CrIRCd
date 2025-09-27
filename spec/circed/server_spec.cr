describe Circed::Server do
  # Tests for server functionality

  it "should return name" do
    Circed::Server.name.should eq("localhost")
  end

  it "should return port" do
    Circed::Server.address.should eq(":localhost")
  end

  it "should return clean_name with :" do
    Circed::Server.clean_name.should eq(":localhost")
  end
end
