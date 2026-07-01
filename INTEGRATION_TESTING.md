# Integration Testing Framework

This document describes the comprehensive integration testing framework for the Circed IRC server, specifically designed to test SSL/TLS functionality and the complete IRC protocol flow.

## Overview

The integration testing framework provides:

- **Real server testing**: Tests run against actual server instances, not mocks
- **SSL/TLS validation**: Comprehensive SSL connection and encryption testing
- **Multi-server scenarios**: Server-to-server linking and network synchronization
- **Protocol compliance**: Full IRC protocol testing with real client connections
- **Performance validation**: Tests under load and stress conditions

## Architecture

### Test Framework Components

1. **`spec/support/integration_helper.cr`** - Core testing framework
2. **Test Specs** - Located in `spec/integration/`
3. **Test Runner** - `run_integration_tests.sh` script
4. **SSL Certificates** - Auto-generated test certificates

### Key Classes

#### `TestEnvironment`
Manages the complete test environment including:
- Server lifecycle (start/stop)
- SSL certificate generation
- Network configuration
- Cleanup operations

```crystal
env = TestEnvironment.new
env.setup_single_server(ssl_enabled: true)
env.setup_linked_servers(ssl_enabled: true)
```

#### `TestClient`
Real IRC client with SSL support:
- SSL/TLS connections
- IRC protocol implementation
- Response validation
- Timeout handling

```crystal
client = env.create_client("Alice", ssl: true)
client.register
client.join("#test")
client.privmsg("#test", "Hello!")
```

#### `ConfigBuilder`
Dynamic server configuration for tests:
- SSL settings
- Port configuration
- Server linking
- Test-specific parameters

```crystal
ConfigBuilder.build("test_server") do |c|
  c.ssl_enabled(true)
  c.ssl_port(16697)
  c.add_linked_server("localhost", 17697)
end
```

## Test Suites

### 1. SSL Connection Tests (`ssl_connection_spec.cr`)

Tests SSL/TLS functionality:
- ✅ SSL client connections
- ✅ Certificate validation
- ✅ Encryption throughout session
- ✅ Multiple concurrent connections
- ✅ Performance with SSL overhead
- ✅ Rapid connect/disconnect cycles

**Example Test:**
```crystal
it "maintains SSL encryption throughout session" do
  env.setup_single_server(ssl_enabled: true)

  client = env.create_client("TestUser", ssl: true)
  client.register

  assert_welcome_sequence(client)
  client.join("#test")
  client.privmsg("#test", "Hello SSL world!")

  client.quit
end
```

### 2. Server Linking Tests (`server_linking_spec.cr`)

Tests server-to-server SSL links:
- ✅ SSL link establishment
- ✅ User synchronization across servers
- ✅ Message routing between servers
- ✅ Network topology maintenance
- ✅ Link authentication
- ✅ Graceful disconnection handling

**Example Test:**
```crystal
it "routes messages between linked servers" do
  env.setup_linked_servers(ssl_enabled: true)

  alice = env.create_client("Alice", port: 16697)  # Server 1
  bob = env.create_client("Bob", port: 17697)      # Server 2

  alice.register
  bob.register
  alice.join("#test")
  bob.join("#test")

  alice.privmsg("#test", "Cross-server message!")
  assert_message_received(bob, "Cross-server message!", "Alice")
end
```

### 3. IRC Protocol Tests (`irc_protocol_spec.cr`)

Tests IRC protocol compliance:
- ✅ User registration sequence
- ✅ Nick collision handling
- ✅ Command validation
- ✅ Error responses
- ✅ PING/PONG handling
- ✅ User modes and away status

### 4. Channel Operations Tests (`channel_operations_spec.cr`)

Tests channel functionality:
- ✅ Channel creation and destruction
- ✅ User permissions and modes
- ✅ Topic management
- ✅ Channel bans and kicks
- ✅ NAMES/WHO commands
- ✅ Cross-server channel synchronization

### 5. Message Routing Tests (`message_routing_spec.cr`)

Tests message delivery:
- ✅ Local message routing
- ✅ Cross-server message routing
- ✅ Private messages
- ✅ Channel messages
- ✅ NOTICE and CTCP handling
- ✅ Loop prevention
- ✅ Error handling

## Running Tests

### Quick Start

```bash
# Run fast non-integration specs
scripts/test fast

# Run all integration tests
scripts/test integration

# Run fast and integration specs sequentially
scripts/test all

# Run specific test suite
crystal spec spec/integration/ssl_connection_spec.cr

# Run with verbose output
crystal spec spec/integration/ --verbose

# Run just SSL tests
crystal spec spec/integration/ssl_connection_spec.cr

# Run server linking tests
crystal spec spec/integration/server_linking_spec.cr
```

### Test Environment Setup

The framework automatically (via Spec hooks):
1. Builds the server binary if needed
2. Generates SSL certificates if missing
3. Cleans up previous test runs
4. Creates test directories
5. Manages server lifecycle
6. Provides automatic cleanup

### Prerequisites

- Crystal compiler
- OpenSSL development libraries
- Working directory write permissions
- Available ports (16667, 16697, 17667, 17697)

## Test Assertions

### IRC Protocol Assertions

```crystal
# Welcome sequence validation
assert_welcome_sequence(client)

# IRC numeric responses
assert_irc_numeric(response, 001)  # RPL_WELCOME
assert_irc_command(response, "JOIN")

# Channel operations
assert_channel_joined(client, "#test")
assert_message_received(client, "Hello", "Alice")
```

### Response Validation

```crystal
# Expect specific response
client.should_receive(/001.*Welcome/)

# Expect no response
client.should_not_receive(/ERROR/, timeout: 1.second)

# Wait for pattern with timeout
response = client.wait_for_response(/PONG/, timeout: 2.seconds)
```

## SSL Certificate Management

Test certificates are automatically generated in `spec/fixtures/ssl/`:

```
spec/fixtures/ssl/
├── ca/
│   ├── ca.crt          # Certificate Authority
│   └── ca.key          # CA private key
├── server1/
│   ├── server.crt      # Server 1 certificate
│   └── server.key      # Server 1 private key
└── server2/
    ├── server.crt      # Server 2 certificate
    └── server.key      # Server 2 private key
```

Certificates are:
- Self-signed for testing
- Valid for 365 days
- Support localhost and IP addresses
- Automatically regenerated if missing

## Configuration Management

Dynamic configuration files are created in `spec/fixtures/`:

```yaml
# Example generated config
host: "0.0.0.0"
port: 16667
network: "TestNetwork"
ssl:
  enabled: true
  port: 16697
  cert_file: "spec/fixtures/ssl/server1/server.crt"
  key_file: "spec/fixtures/ssl/server1/server.key"
linked_servers:
  - host: "localhost"
    port: 17697
    use_ssl: true
```

## Performance Testing

The framework includes performance tests:

```crystal
it "maintains performance with SSL overhead" do
  client = env.create_client("TestUser", ssl: true)
  client.register

  start_time = Time.monotonic

  100.times do |i|
    client.send("PING :test#{i}")
    client.should_receive(/PONG.*test#{i}/)
  end

  elapsed = Time.monotonic - start_time
  elapsed.should be < 5.seconds
end
```

## Error Handling

Comprehensive error handling includes:
- Server startup failures
- SSL handshake errors
- Protocol violations
- Network timeouts
- Resource cleanup

## Best Practices

### Writing Integration Tests

1. **Use descriptive test names**
   ```crystal
   it "propagates nick changes across linked servers" do
   ```

2. **Clean up resources**
   ```crystal
   after_each do
     env.teardown  # Automatically stops servers and cleans up
   end
   ```

3. **Use appropriate timeouts**
   ```crystal
   client.should_receive(/PONG/, timeout: 2.seconds)
   ```

4. **Test both success and failure cases**
   ```crystal
   it "handles invalid nicknames" do
     client.send("NICK Invalid Nick")
     client.should_receive(/432.*Erroneous nickname/)
   end
   ```

### Performance Considerations

- Tests run real servers (slower than unit tests)
- Each test suite runs in isolation
- Automatic cleanup between tests
- Parallel execution not recommended

## Troubleshooting

### Common Issues

1. **Port conflicts**
   - Kill existing processes: `pkill -f circed_test`
   - Check port availability: `lsof -i :16697`

2. **SSL certificate errors**
   - Delete and regenerate: `rm -rf spec/fixtures/ssl/`
   - Check OpenSSL installation

3. **Test timeouts**
   - Increase timeout values for slow systems
   - Check server logs in `spec/logs/`

4. **Permission errors**
   - Ensure write permissions to `spec/` directory
   - Check SSL certificate permissions

### Debug Mode

Enable verbose logging:
```bash
CIRCED_DEBUG=true crystal spec spec/integration/ssl_connection_spec.cr
```

## Continuous Integration

The integration tests are designed for CI environments:

```bash
# CI-friendly execution
./run_integration_tests.sh || exit 1

# Generate JUnit XML output
crystal spec spec/integration/ --junit_output=test_results.xml
```

## Extending the Framework

### Adding New Test Suites

1. Create new spec file in `spec/integration/`
2. Include the integration helper
3. Use `TestEnvironment` for setup
4. Add to test runner script

### Custom Assertions

```crystal
module CustomAssertions
  def assert_server_linked(server1, server2)
    # Custom assertion logic
  end
end

include CustomAssertions
```

### Test Utilities

Add helper methods to `integration_helper.cr`:

```crystal
def wait_for_server_link(env, timeout = 5.seconds)
  # Helper implementation
end
```

This integration testing framework ensures the IRC server works correctly in real-world scenarios with SSL/TLS encryption and multi-server deployments.
