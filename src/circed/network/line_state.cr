require "file_utils"

module Circed
  module Network
    module LineState
      @@lines = Hash(String, Domain::LineBan).new
      @@mutex = Mutex.new
      @@database_path = "data/lines.yml"
      @@persistence_enabled = ENV["CIRCED_TEST"]? != "true" || ENV.has_key?("CIRCED_LINE_DB")

      def self.configure_persistence(path : String, enabled : Bool = true) : Nil
        @@mutex.synchronize do
          @@database_path = path
          @@persistence_enabled = enabled
          load_from_disk_locked if enabled
        end
      end

      def self.add(type : String, mask : String, reason : String, set_by : String, duration : Time::Span? = nil) : Domain::LineBan?
        add_until(type, mask, reason, set_by, duration ? Time.utc + duration : nil)
      end

      def self.add_until(type : String, mask : String, reason : String, set_by : String, expires_at : Time?) : Domain::LineBan?
        normalized_type = normalize_type(type)
        return unless normalized_type
        normalized_mask = normalize_mask(normalized_type, mask)
        return if normalized_mask.empty?

        line = Domain::LineBan.new(normalized_type, normalized_mask, reason, set_by, Time.utc, expires_at)

        @@mutex.synchronize do
          key = line.key
          existing = @@lines[key]?
          return if existing && same_line?(existing, line)

          @@lines[key] = line
          save_to_disk_locked
          line
        end
      end

      def self.remove(type : String, mask : String) : Bool
        normalized_type = normalize_type(type)
        return false unless normalized_type
        normalized_mask = normalize_mask(normalized_type, mask)
        return false if normalized_mask.empty?

        @@mutex.synchronize do
          removed = @@lines.delete(Domain::LineBan.key(normalized_type, normalized_mask))
          save_to_disk_locked if removed
          !removed.nil?
        end
      end

      def self.enforce(line : Domain::LineBan) : Nil
        user_repository = Infrastructure::ServiceLocator.user_repository
        user_repository.each_client do |client|
          next unless context = client.ban_match_context
          next unless line.matches?(context)

          client.send_error("#{line.type}: #{line.reason}")
          client.shutdown
        end
      end

      def self.matching(context : Domain::BanMatchContext) : Domain::LineBan?
        @@mutex.synchronize do
          prune_expired_locked

          hostmask_match = nil
          @@lines.each_value do |line|
            next unless line.matches?(context)
            return line if line.type == Domain::LineBan::ZLINE

            hostmask_match ||= line
          end
          hostmask_match
        end
      end

      def self.each(& : Domain::LineBan ->) : Nil
        @@mutex.synchronize do
          prune_expired_locked
          @@lines.each_value do |line|
            yield line
          end
        end
      end

      def self.clear : Nil
        @@mutex.synchronize do
          @@lines.clear
          save_to_disk_locked
        end
      end

      def self.normalize_mask(type : String, mask : String) : String
        normalized_type = type.upcase
        normalized = mask.strip
        return "" if normalized.empty?

        if normalized_type == Domain::LineBan::ZLINE
          if at_index = normalized.rindex('@')
            normalized = normalized[(at_index + 1)..]
          end
          return normalized.downcase
        end

        if normalized.includes?('@')
          normalized = "*!#{normalized}" unless normalized.includes?('!')
        else
          normalized = "*!*@#{normalized}"
        end
        normalized.downcase
      end

      private def self.normalize_type(type : String) : String?
        normalized = type.upcase
        Domain::LineBan::TYPES.includes?(normalized) ? normalized : nil
      end

      private def self.same_line?(left : Domain::LineBan, right : Domain::LineBan) : Bool
        left.reason == right.reason &&
          left.set_by == right.set_by &&
          left.expires_at.try(&.to_unix) == right.expires_at.try(&.to_unix)
      end

      private def self.prune_expired_locked : Nil
        before_size = @@lines.size
        @@lines.reject! { |_, line| line.expired? }
        save_to_disk_locked if @@lines.size != before_size
      end

      private def self.load_from_disk_locked : Nil
        @@lines.clear

        File.open(@@database_path) do |file|
          Array(Domain::LineBan).from_yaml(file) do |line|
            next if line.expired?

            @@lines[line.key] = line
          end
        end
      rescue File::NotFoundError
      rescue ex
        Log.warn(exception: ex) { "Failed to load line database #{@@database_path}" }
      end

      private def self.save_to_disk_locked : Nil
        return unless @@persistence_enabled

        FileUtils.mkdir_p(File.dirname(@@database_path))

        File.open(@@database_path, "w") do |file|
          @@lines.each_value.to_yaml(file)
        end
      rescue ex
        Log.warn(exception: ex) { "Failed to save line database #{@@database_path}" }
      end
    end
  end
end
