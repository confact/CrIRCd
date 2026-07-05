# IRC Services Multi-Server Network Design Note

This document is aspirational. The current source tree does not implement
ChanServ, UserServ, `services_server`, SQLite-backed services persistence, or
the `SVS*` synchronization commands described below. Treat this as a design note
for a future services subsystem, not as supported configuration.

## Overview

The proposed IRC services (ChanServ, UserServ) would work across multiple servers in an IRC network. Here's how that design handles multi-server scenarios:

## Architecture

### 🏢 **Centralized Services Model**

- **One Services Server**: Only one server in the network hosts the actual services
- **Network-Wide Access**: Users on any server can interact with services
- **Automatic Routing**: Messages to services are automatically routed to the services server
- **Data Synchronization**: All servers receive updates about registrations and changes

### 🔄 **Message Flow**

```
User on Server A → PRIVMSG ChanServ → Routes to Services Server → Response sent back
User on Server B → PRIVMSG UserServ → Routes to Services Server → Response sent back
```

## Configuration

### Services Server Setup

```bash
# Use configuration file with services_server: true
./circed config_services.yml
```

### Regular Server Setup

```bash
# Use configuration file with services_server: false (or omit it)
./circed config_regular.yml
```

### Configuration Files

**Services Server (config_services.yml):**
```yaml
host: "services.irc.network.com"
port: 6667
network: "ExampleNet"
max_users: 1000
link_password: "linking_password"
services_server: true  # This server hosts ChanServ and UserServ

linked_servers:
  - host: "hub.irc.network.com"
    port: 6667
    link_password: "linking_password"
```

**Regular Server (config_regular.yml):**
```yaml
host: "leaf1.irc.network.com"
port: 6667
network: "ExampleNet"
max_users: 500
link_password: "linking_password"
services_server: false  # This server does NOT host services (default)

linked_servers:
  - host: "services.irc.network.com"
    port: 6667
    link_password: "linking_password"
```

## Network Protocols

### Services Synchronization Commands

The following commands are used for server-to-server services synchronization:

#### User Registration Sync
```
SVSREGISTER nickname password_hash [email]
```

#### User Identification Sync
```
SVSIDENTIFY nickname IDENTIFIED|UNIDENTIFIED
```

#### Channel Registration Sync
```
SVSREGCHAN #channel founder modes [:topic]
```

#### Channel Access Sync
```
SVSACCESS #channel nickname access_level added_by
SVSREMACCESS #channel nickname
```

#### Channel Management
```
SVSDROPCHAN #channel
```

#### Services Server Announcement
```
SERVICES server_name
```

## Network Scenarios

### 🔗 **Server Linking**

When a new server links to the network:

1. **Services Server Discovery**: New server receives `SERVICES services.irc.network.com`
2. **Data Synchronization**: Services server sends full database sync
3. **Service Registration**: Virtual service users (ChanServ, UserServ) are introduced

### 💥 **Server Split**

When servers disconnect:

1. **Services Server Loss**: If services server disconnects, services become unavailable
2. **Automatic Reconnection**: Regular servers continue trying to reconnect
3. **Data Persistence**: Services data is preserved in SQLite database

### 🔄 **Services Server Migration**

To migrate services to a different server:

1. Stop services server
2. Copy `services.db` to new server
3. Start new server with `SERVICES_SERVER=true`
4. New server announces itself as services server

## Usage Examples

### From Any Server in Network

```irc
# User on server1.network.com
/msg UserServ REGISTER mypassword user@example.com

# User on server2.network.com
/msg ChanServ REGISTER #mychannel password

# User on server3.network.com
/whois someuser
# Shows: someuser is a registered nick (if registered)
```

### Network Topology Example

```
services.irc.network.com (Services Server)
├── hub1.irc.network.com
│   ├── leaf1.irc.network.com
│   └── leaf2.irc.network.com
└── hub2.irc.network.com
    ├── leaf3.irc.network.com
    └── leaf4.irc.network.com
```

## Data Flow

### Registration Process

1. **User Action**: `/msg UserServ REGISTER password` (any server)
2. **Routing**: Message routed to services server
3. **Processing**: Services server processes registration
4. **Database**: Data stored in SQLite
5. **Broadcast**: Registration synced to all servers
6. **Response**: Success message sent back to user

### Channel Auto-Management

1. **User Joins**: User joins registered channel on any server
2. **Detection**: Server detects channel is registered
3. **Query**: Checks services data (local cache or services server)
4. **Application**: Applies modes, topic, access levels automatically

## Monitoring & Debugging

### Log Messages

Services server:
```
[INFO] This server is now the services server
[INFO] IRC Services initialized: ChanServ, UserServ
```

Regular servers:
```
[INFO] Services server is: services.irc.network.com
[DEBUG] User nickname identified on remote server
```

### Network Commands

Check services status:
```
/msg ChanServ INFO #channel  # Works from any server
/msg UserServ INFO nickname  # Works from any server
```

## Security Considerations

- **Encrypted Linking**: Use SSL for server-to-server connections
- **Password Security**: BCrypt hashing for all passwords
- **Access Control**: Only authorized servers can link and sync data
- **Data Integrity**: Database constraints prevent corruption

## Performance

- **Local Caching**: Frequently accessed data cached on each server
- **Efficient Routing**: Direct routing to services server minimizes hops
- **Database Optimization**: SQLite with proper indexes for fast queries
- **Network Efficiency**: Only changes are broadcast, not full data

This architecture ensures that IRC services work seamlessly across the entire network while maintaining data consistency and high availability.
