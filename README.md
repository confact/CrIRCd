# CrIRCd - IRCD (daemon) in Crystal

A Crystal IRC server implementation that follows IRC protocol specifications. While not yet 100% spec-compliant, it provides a solid foundation for IRC server functionality.

## Features

### Core IRC Functionality
* User connections and authentication
* MOTD and server statistics
* PING/PONG with automatic disconnection after 3 missed pings
* Private messages between users
* Channel support with standard operations:
  * Join, part, and messaging
  * Kick and invite users
  * Topic management
  * Channel modes (private, secret, password-protected, user limit)
  * Ban lists with extended matching for nick, username, hostname, realname,
    joined channel, and hostmask plus realname masks
* User information lookup (IP, hostname, WHOIS)
* Activity and signon time tracking
* IRC operator authentication with `OPER`
* Oper-only administrative commands: `KILL`, `REHASH`, `CONNECT`, `SQUIT`,
  `DIE`, `RESTART`, `KLINE`, `GLINE`, and `ZLINE`

### Network & Security
* **SSL/TLS Support** - Secure connections for clients and servers
* **Server-to-Server Communication** - Build IRC networks with multiple linked servers
* **Server Link Recovery** - Configured outgoing links retry with capped backoff,
  clean up unreachable servers and users after a netsplit, and burst current
  network state after reconnecting
* **STARTTLS** - Upgrade plain connections to encrypted
* **Flood Protection** - Per-client token-bucket command rate limiting, with
  higher costs for expensive queries
* **Protocol Limits** - Enforces the IRC 512-byte input-line limit
* **Slow-client Protection** - Bounded, batched outbound queues prevent socket
  writes from blocking command and channel fanout

### Planned Features
* Additional channel and user modes

### Not Implemented
* NickServ, ChanServ, and persistent IRC services


## Quick Start

### Requirements
* Crystal >= 1.4

### Installation
1. Clone this repository
2. Build the server: `crystal build --release ./src/circed.cr`
3. Run the server: `./circed`

### Basic Configuration
The configuration is in `config.yml`. Basic settings include:

```yaml
host: "0.0.0.0"
port: 6667
network: "MyIRCNetwork"
max_users: 100
link_password: "server_link_password"
line_database: "data/lines.yml"
allow_die: false
allow_restart: false
```

### IRC Operators

IRC operators are configured with O-line style entries under `operators`.
Clients authenticate with `OPER <name> <password>`. On success, CrIRCd sends
`381 RPL_YOUREOPER` and sets user mode `+o` for global operators or `+O` for
local operators. Users cannot grant themselves `+o` or `+O` with `MODE`; those
modes must come from `OPER`, though users may remove their own operator mode.
Operators can use `KILL <nickname> :<reason>` to disconnect users, `REHASH` to
reload config, `CONNECT` to start a configured server link, and `SQUIT` to drop
a server link. `DIE` and `RESTART` are disabled by default and require
`allow_die: true` or `allow_restart: true`.

CrIRCd supports IRCd-style line bans for operators. These are common IRCd
extensions, not RFC core commands. `KLINE <user@host> [duration] :<reason>` adds
a local user@host ban, `GLINE <user@host> [duration] :<reason>` adds a
network-wide user@host ban across linked CrIRCd servers, and
`ZLINE <ip-or-cidr> [duration] :<reason>` adds a local IP ban. Calling the same
command with only a mask removes the line, for example `GLINE *@bad.example`.
Durations can be seconds or compound values like `1w2d3h`; omit the duration or
use `0` for a permanent line. Active lines are stored in `line_database`.

Users can set `MODE <nick> +w` to receive wallops notices from linked servers.
CrIRCd treats `WALLOPS` as a server-originated command and does not expose it as
a client operator command.

```yaml
operators:
  - name: "admin"
    password: "change-this-password"
    hosts:
      - "*!admin@trusted.example.com"
      - "trusted.example.com"

  - name: "local-admin"
    password: "change-this-too"
    local: true
    hosts:
      - "localhost"
      - "*!oper@127.0.0.1"
```

`hosts` is optional and defaults to `["*"]`. Host masks are matched
case-insensitively with `*` and `?` wildcards against the user's hostmask,
resolved hostname, and socket host string. Prefer restrictive host masks in
production.

## Testing

Use the focused test helper during development:

```bash
# Fast unit-level specs
scripts/test fast

# Real server integration specs
scripts/test integration

# Both suites
scripts/test all
```

The integration specs bind fixed local ports and should be run sequentially.

## Benchmarks and Capacity

CrIRCd uses `max_users` as the configured local-client limit. Real concurrency is
also bounded by the operating system file-descriptor limit, memory, TLS overhead,
channel fanout size, and server-to-server links. Set `max_users` below the
process file-descriptor limit with room for listening sockets, linked servers,
logs, and outbound files.

Reference benchmark on an Apple M1 Pro with 16 GB RAM, Crystal 1.17.1, release
build, `LOG_LEVEL=ERROR`, and `ulimit -n 8192`. The local load generator runs
concurrent client fibers against the server and sends `QUIT` before closing each
test socket:

* 3,500 local clients registered and joined channels in 0.46-0.57 seconds with
  128 client workers (~6,200-7,700 clients/s across two consecutive runs).
* The same 3,500-client run measured ~5,500 clients/s with 64 workers and
  ~5,100 clients/s with 256 workers on this host.
* 5,000 local clients registered and joined 250 channels in 0.70 seconds with
  128 client workers (~7,100 clients/s).

The largest local socket benchmark run completed with 5,000 concurrent connected
clients spread across 250 channels. This is the current benchmark config limit,
not a hard architectural limit. Larger deployments should raise `max_users`,
raise file-descriptor limits, and benchmark on the target host. As a rule of
thumb, a single process needs at least one file descriptor per local client plus
headroom for listeners, server links, logs, and outbound files.

The in-memory channel index benchmark uses 20,000 users, 5,000 channels, and
100,000 user-channel memberships:

* Indexed user-channel lookups: 100,000 queries in 6.83 ms
  (~14.7 million lookups/s).
* Old scan-style lookup over all channels: 100,000 queries in 10.19 seconds
  (~9,800 lookups/s).
* Removing 20,000 users from all joined channels: 15.09 ms.

That supports IRC networks with tens of thousands of users and thousands of
channels for membership-heavy operations on one process, assuming channel sizes
and message rates are reasonable. Server-to-server networks should be kept to
tens of directly linked servers until route-table caching and burst benchmarks
are added; message propagation still fans out to linked servers. For large
public networks, split users across linked servers and keep very large channels
rare, because every channel message is still delivered to each recipient.

CrIRCd uses bounded Crystal channels for per-client and server-link outbound
queues, with writer fibers batching socket writes. Channel fanout remains a
direct membership iteration instead of one pipe per IRC channel: Crystal
channels are best used to communicate between fibers, while channel message
delivery still has to visit each recipient. Extra per-channel pipes would add
scheduling and backpressure overhead without reducing the O(channel members)
delivery cost.

To target 7,000-10,000 registrations per second, run release builds with low log
volume, keep DNS asynchronous with a small registration wait, raise file
descriptor limits, keep slow clients from blocking fanout with bounded outbound
queues, and benchmark with realistic channel sizes and TLS settings.

Run the benchmarks with:

```bash
crystal run --release benchmarks/channel_repository_benchmark.cr

crystal build --release -o bin/circed src/circed.cr
ulimit -n 8192
LOG_LEVEL=ERROR bin/circed benchmarks/benchmark_config.yml
```

Then, from another shell with the same descriptor limit:

```bash
ulimit -n 8192
crystal run --release benchmarks/local_client_load.cr -- 127.0.0.1 16680 3500 175 2 128
```

## Supported IRC Surface

CrIRCd currently supports these client-facing commands:

* Registration and connection: `NICK`, `USER`, `PASS`, `CAP`, `PING`, `PONG`,
  `QUIT`, `AWAY`, `STARTTLS`
* Messaging: `PRIVMSG`, `NOTICE`
* Channels: `JOIN`, `PART`, `MODE`, `TOPIC`, `INVITE`, `KICK`, `NAMES`, `LIST`,
  `WHO`
* Operator commands: `OPER`, `KILL`, `REHASH`, `CONNECT`, `SQUIT`, `DIE`,
  `RESTART`, `KLINE`, `GLINE`, `ZLINE`
* User/server queries: `WHOIS`, `ISON`, `USERHOST`, `LUSERS`, `MOTD`, `LINKS`,
  `STATS`, `TIME`, `VERSION`, `ADMIN`

Server-to-server links support handshake, burst, channel membership, user state,
message routing, global line-ban synchronization, server query propagation, and
netsplit cleanup with state recovery after reconnection.

Unsupported areas include persistent IRC services.

## Configuration Reload

The server watches the config file and reloads scalar configuration into memory,
but runtime sockets are not reconciled after reload. Restart the process after
changing bind host, ports, SSL certificates, linked servers, or limits that need
to affect already-running listeners and links.

## DNS Hostnames

Client hostnames are resolved asynchronously. New clients start with their IP
address immediately, then CrIRCd queues a reverse DNS lookup. Before sending the
registration welcome, the client waits up to `dns.registration_wait_ms` for a
verified hostname. If DNS is slow, unavailable, or the PTR result does not
forward-confirm back to the client IP, the IP address remains the hostname.

```yaml
dns:
  enabled: true
  server: "8.8.8.8"
  port: 53
  workers: 4
  queue_size: 1024
  timeout_seconds: 1
  registration_wait_ms: 100
  cache_ttl_seconds: 3600
  negative_cache_ttl_seconds: 300
```

Keep `registration_wait_ms` small on high-throughput servers. Increase
`workers` only if DNS latency is high and the queue backs up.

## SSL/TLS Configuration

CrIRCd supports secure connections using SSL/TLS for both clients and server-to-server communication.

### Quick SSL Setup

1. **Generate test certificates:**
   ```bash
   ./generate_ssl_certs.sh
   ```

2. **Enable SSL in config.yml:**
   ```yaml
   ssl:
     enabled: true
     port: 6697
     cert_file: "ssl/server.crt"
     key_file: "ssl/server.key"
     starttls: true
   ```

3. **Start the server and connect:**
   ```bash
   ./circed config.yml

   # Connect with SSL client
   openssl s_client -connect localhost:6697
   ```

### Advanced SSL Configuration

For production deployments with certificate verification:

```yaml
ssl:
  enabled: true
  port: 6697
  cert_file: "/path/to/server.crt"
  key_file: "/path/to/server.key"
  ca_file: "/path/to/ca.crt"        # For client cert verification
  verify_mode: true                 # Verify client certificates
  starttls: true                    # Allow STARTTLS upgrade
  require_ssl_for_servers: false    # Require SSL for server links
```

### Server-to-Server SSL

Configure encrypted server links:

```yaml
linked_servers:
  - host: "irc2.example.com"
    server_name: "irc2.example.com"
    port: 6697
    link_password: "secure_password"
    use_ssl: true
    verify_ssl: true  # Verify server certificate
```

### Client Connection Methods

**Direct SSL Connection (Port 6697):**
```bash
# IRC clients
irssi -c irc.example.com -p 6697 --ssl

# Testing with OpenSSL
openssl s_client -connect localhost:6697
```

**STARTTLS Upgrade (Port 6667):**
```
STARTTLS
# Server responds: 670 :STARTTLS successful, proceed with TLS handshake
# Client performs TLS handshake
```

### SSL Security Features

* **Modern TLS:** TLS 1.2+ only (SSLv2, SSLv3, TLS 1.0/1.1 disabled)
* **Secure Ciphers:** ECDHE+AESGCM, ECDHE+CHACHA20, DHE+AESGCM
* **Certificate Verification:** Optional mutual TLS with client certificates
* **STARTTLS Support:** RFC-compliant connection upgrade

### Production SSL Considerations

1. **Use Valid Certificates:** Obtain from trusted CA (Let's Encrypt recommended)
2. **Secure Key Storage:** Set appropriate file permissions (600 for private keys)
3. **Certificate Renewal:** Implement automatic renewal processes
4. **Monitoring:** Log SSL handshake success/failures for security monitoring

## Known issues
* Config reload does not recreate already-running sockets or server links

## Contributions
Everyone is welcome to contribute. Fork this repo, make your changes and make a Pull Request explaining what you did and why. And I and others will review it and merge it if it make sense. :)

## Maintainers:
* Håkan Nylén - @confact
