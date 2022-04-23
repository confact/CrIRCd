describe Circed::Server do
  # TODO: Write tests

  it "should return name" do
    Circed::Server.name.should eq("irc.erro.sh")
  end

  it "should return port" do
    Circed::Server.address.should eq(":::1")
  end

  it "should return clean_name with :" do
    Circed::Server.clean_name.should eq(":irc.erro.sh")
  end
end