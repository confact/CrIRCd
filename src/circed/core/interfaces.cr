# Core abstractions and interfaces for the IRC server
module Circed
  module Core
    # Base repository interface for managing entities
    module Repository(T)
      include Enumerable(T)

      abstract def []?(id : String) : T?
      abstract def []=(id : String, entity : T) : T
      abstract def delete(id : String) : T?
      abstract def each(& : T ->) : Nil
      abstract def size : Int32
      abstract def clear : Nil
    end
  end
end
