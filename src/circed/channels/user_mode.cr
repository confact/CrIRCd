module Circed
  class UserMode
    VALID_MODES = ["o", "h", "v"]
    MODE_HASH = {
      "o" => "@",
      "h" => "%",
      "v" => "+"
    }

    getter mode : String = ""

    def initialize(mode = "")
      @mode = mode
    end

    def to_s
      @mode
    end

    def add(mode)
      if VALID_MODES.includes?(mode)
        @mode += mode unless @mode.includes?(mode)
      else
        raise Exception.new("Invalid mode: #{mode}")
      end
    end

    def remove(mode)
      if VALID_MODES.includes?(mode)
        @mode = @mode.sub(mode, "")
      else
        raise Exception.new("Invalid mode: #{mode}")
      end
    end

    def highest_mode : String
      VALID_MODES.sort.reverse!.each do |mode|
        if @mode.includes?(mode)
          return MODE_HASH[mode]
        end
      end
      ""
    end

    def has_mode?(mode)
      @mode.includes?(mode)
    end

    def has_any_mode?(modes)
      modes.any? { |mode| has_mode?(mode) }
    end

    def has_all_modes?(modes)
      modes.all? { |mode| has_mode?(mode) }
    end

    def is_operator?
      @mode.includes?("o")
    end

    def is_half_operator?
      @mode.includes?("h")
    end

    def is_voiced?
      @mode.includes?("v")
    end
  end
end
