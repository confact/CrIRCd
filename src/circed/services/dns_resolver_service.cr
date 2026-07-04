require "durian"

module Circed
  module Services
    class DNSResolverService
      record Request, ip_address : String, result : Channel(String?)
      record CacheEntry, hostname : String?, expires_at : Time

      getter registration_wait : Time::Span

      @requests : Channel(Request)
      @cache = Hash(String, CacheEntry).new
      @cache_mutex = Mutex.new
      @dns_server : Socket::IPAddress

      def initialize(@config : Config::DNSConfig)
        @requests = Channel(Request).new(@config.queue_size)
        @registration_wait = @config.registration_wait_ms.milliseconds
        @dns_server = Socket::IPAddress.new(@config.server, @config.port)
        start_workers if @config.enabled?
      end

      def resolve_async(ip_address : String) : Channel(String?)?
        return nil unless @config.enabled?
        return nil unless resolvable_ip?(ip_address)

        result = Channel(String?).new(1)
        if cached = cached_entry?(ip_address)
          result.send(cached.hostname)
          return result
        end

        select
        when @requests.send(Request.new(ip_address, result))
          result
        else
          nil
        end
      end

      def receive_result(result : Channel(String?), timeout : Time::Span = @registration_wait) : String?
        select
        when hostname = result.receive?
          hostname
        when timeout(timeout)
          nil
        end
      end

      private def start_workers : Nil
        worker_count = @config.workers > 0 ? @config.workers : 1
        worker_count.times do
          spawn do
            worker_loop
          end
        end
      end

      private def worker_loop : Nil
        resolver = build_resolver

        while request = @requests.receive?
          begin
            hostname = resolve_verified_hostname(resolver, request.ip_address)
            cache_hostname(request.ip_address, hostname)
            request.result.send(hostname) unless request.result.closed?
          rescue Channel::ClosedError
          rescue ex
            Log.debug(exception: ex) { "DNS resolver worker failed" }
          end
        end
      end

      private def build_resolver : Durian::Resolver
        resolver = Durian::Resolver.new(@dns_server, Durian::Protocol::UDP)
        resolver.option.timeout.read = @config.timeout_seconds
        resolver.option.timeout.write = @config.timeout_seconds
        resolver.option.timeout.connect = @config.timeout_seconds
        resolver
      end

      private def resolve_verified_hostname(resolver : Durian::Resolver, ip_address : String) : String?
        reverse_name = reverse_dns_name(ip_address)
        return nil unless reverse_name
        return nil unless hostname = lookup_ptr(resolver, reverse_name)
        return nil unless hostname_resolves_to_ip?(resolver, hostname, ip_address)

        hostname.rstrip('.')
      end

      private def lookup_ptr(resolver : Durian::Resolver, reverse_name : String) : String?
        packets = resolver.query_record!(nil, reverse_name, Durian::RecordFlag::PTR, true)
        packets.try &.each do |packet|
          packet.answers.each do |answer|
            if record = answer.resourceRecord.as?(Durian::Record::PTR)
              return record.domainName unless record.domainName.empty?
            end
          end
        end
      rescue ex
        Log.debug(exception: ex) { "PTR lookup failed for #{reverse_name}" }
      end

      private def hostname_resolves_to_ip?(resolver : Durian::Resolver, hostname : String, ip_address : String) : Bool
        lookup_addresses(resolver, hostname).any? { |address| address == ip_address }
      end

      private def lookup_addresses(resolver : Durian::Resolver, hostname : String) : Array(String)
        addresses = [] of String
        lookup_a_records(resolver, hostname, addresses)
        lookup_aaaa_records(resolver, hostname, addresses)
        addresses
      end

      private def lookup_a_records(resolver : Durian::Resolver, hostname : String, addresses : Array(String)) : Nil
        packets = resolver.query_record!(nil, hostname, Durian::RecordFlag::A, true)
        packets.try &.each do |packet|
          packet.answers.each do |answer|
            if record = answer.resourceRecord.as?(Durian::Record::A)
              if address = record.ipv4Address
                addresses << address.address
              end
            end
          end
        end
      rescue ex
        Log.debug(exception: ex) { "A lookup failed for #{hostname}" }
      end

      private def lookup_aaaa_records(resolver : Durian::Resolver, hostname : String, addresses : Array(String)) : Nil
        packets = resolver.query_record!(nil, hostname, Durian::RecordFlag::AAAA, true)
        packets.try &.each do |packet|
          packet.answers.each do |answer|
            if record = answer.resourceRecord.as?(Durian::Record::AAAA)
              if address = record.ipv6Address
                addresses << address.address
              end
            end
          end
        end
      rescue ex
        Log.debug(exception: ex) { "AAAA lookup failed for #{hostname}" }
      end

      private def cached_entry?(ip_address : String) : CacheEntry?
        @cache_mutex.synchronize do
          entry = @cache[ip_address]?
          return nil unless entry
          if entry.expires_at <= Time.utc
            @cache.delete(ip_address)
            return nil
          end
          entry
        end
      end

      private def cache_hostname(ip_address : String, hostname : String?) : Nil
        ttl = hostname ? @config.cache_ttl_seconds : @config.negative_cache_ttl_seconds
        expires_at = Time.utc + ttl.seconds
        @cache_mutex.synchronize do
          @cache[ip_address] = CacheEntry.new(hostname, expires_at)
        end
      end

      private def resolvable_ip?(ip_address : String) : Bool
        return false if {"localhost", "127.0.0.1", "::1"}.includes?(ip_address)
        Socket::IPAddress.new(ip_address, 0)
        true
      rescue Socket::Error
        false
      end

      private def reverse_dns_name(ip_address : String) : String?
        if ip_address.includes?(':')
          ipv6_reverse_dns_name(ip_address)
        else
          ipv4_reverse_dns_name(ip_address)
        end
      end

      private def ipv4_reverse_dns_name(ip_address : String) : String
        ip_address.split('.').reverse!.join('.') + ".in-addr.arpa"
      end

      private def ipv6_reverse_dns_name(ip_address : String) : String?
        # Socket::IPAddress does not expose packed IPv6 bytes directly in older
        # Crystal versions, so keep IPv6 on IP fallback until the resolver grows
        # a packed-address helper.
        nil
      rescue Socket::Error
        nil
      end
    end
  end
end
