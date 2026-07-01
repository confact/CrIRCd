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

### Network & Security
* **SSL/TLS Support** - Secure connections for clients and servers
* **Server-to-Server Communication** - Build IRC networks with multiple linked servers
* **Server Link Recovery** - Configured outgoing links retry with capped backoff
* **STARTTLS** - Upgrade plain connections to encrypted

### Planned Features
* Additional channel and user modes

### Not Implemented
* IRC operator authentication and oper-only commands
* Network-wide GLines
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
```

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

## Supported IRC Surface

CrIRCd currently supports these client-facing commands:

* Registration and connection: `NICK`, `USER`, `PASS`, `CAP`, `PING`, `PONG`,
  `QUIT`, `AWAY`, `STARTTLS`
* Messaging: `PRIVMSG`, `NOTICE`
* Channels: `JOIN`, `PART`, `MODE`, `TOPIC`, `INVITE`, `KICK`, `NAMES`, `LIST`,
  `WHO`
* User/server queries: `WHOIS`, `LINKS`, `STATS`, `TIME`, `VERSION`, `ADMIN`

Server-to-server links support handshake, burst, channel membership, user state,
message routing, and basic server query propagation.

Unsupported areas include IRC operator authentication, network GLines, and
persistent IRC services.

## Configuration Reload

The server watches the config file and reloads scalar configuration into memory,
but runtime sockets are not reconciled after reload. Restart the process after
changing bind host, ports, SSL certificates, linked servers, or limits that need
to affect already-running listeners and links.

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
