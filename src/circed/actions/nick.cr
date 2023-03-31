module Circed
  class Actions::Nick

    extend Circed::ActionHelper

    def self.call(sender, new_nickname : String)
      if UserHandler.nickname_used?(new_nickname)
        send_error(sender, Numerics::ERR_NICKNAMEINUSE, new_nickname, "Nickname is already in used")
        return
      end
      changed = !sender.nickname.to_s.empty?
      old_nickname = sender.nickname.to_s

      if changed
        begin
          Log.debug { "changing nickname to: #{new_nickname} " }
          UserHandler.changed_nickname(old_nickname.to_s, new_nickname)
          send_to_user(sender) do |_receiver, io|
            parse(sender, [new_nickname], io) if io
          end
          send_to_user_channel(sender) do |receiver, io|
            next if receiver == sender
            parse(sender, [new_nickname], io) if io
          end
          sender.nickname = new_nickname
        rescue e : Exception
          Log.debug { "error, nickname is not used: #{old_nickname} " }
          UserHandler.changed_nickname(new_nickname, old_nickname.to_s)
          sender.nickname = old_nickname
          send_error(sender, Numerics::ERR_ERRONEUSNICKNAME, old_nickname, "Nickname is not used.")
        end
      else
        Log.debug { "Set nickname to: #{new_nickname} " }
        sender.nickname = new_nickname
        send_to_user(sender) do |_receiver, io|
          io << ":#{Server.clean_name} NICK :#{sender.nickname}\n" if io
        end
      end
    end
  end
end
