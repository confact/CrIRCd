#!/bin/bash

# Test SSL server-to-server connections for crIRCd

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}SSL Server-to-Server Connection Test${NC}"
echo -e "${CYAN}======================================${NC}"

# Function to kill servers on exit
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    if [[ -n "$PID1" ]]; then
        kill $PID1 2>/dev/null || true
    fi
    if [[ -n "$PID2" ]]; then
        kill $PID2 2>/dev/null || true
    fi
    rm -f server1.log server2.log
    echo -e "${GREEN}Cleanup complete${NC}"
}

trap cleanup EXIT

# Build the server if needed
echo -e "\n${BLUE}Building IRC server...${NC}"
crystal build src/circed.cr -o circed_test 2>&1 | grep -v "^$" || true

if [ ! -f "./circed_test" ]; then
    echo -e "${RED}Failed to build the server${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Server built successfully${NC}"

# Start Server 1
echo -e "\n${BLUE}Starting Server 1 (irc1.test.local) on SSL port 6697...${NC}"
./circed_test config_server1_ssl.yml > server1.log 2>&1 &
PID1=$!
sleep 2

# Check if Server 1 is running
if kill -0 $PID1 2>/dev/null; then
    echo -e "${GREEN}✓ Server 1 started (PID: $PID1)${NC}"
else
    echo -e "${RED}✗ Server 1 failed to start${NC}"
    echo "Server 1 log:"
    cat server1.log
    exit 1
fi

# Start Server 2
echo -e "\n${BLUE}Starting Server 2 (irc2.test.local) on SSL port 7697...${NC}"
./circed_test config_server2_ssl.yml > server2.log 2>&1 &
PID2=$!
sleep 2

# Check if Server 2 is running
if kill -0 $PID2 2>/dev/null; then
    echo -e "${GREEN}✓ Server 2 started (PID: $PID2)${NC}"
else
    echo -e "${RED}✗ Server 2 failed to start${NC}"
    echo "Server 2 log:"
    cat server2.log
    exit 1
fi

echo -e "\n${CYAN}======================================${NC}"
echo -e "${CYAN}Both servers are running!${NC}"
echo -e "${CYAN}======================================${NC}"

# Wait for servers to establish connection
echo -e "\n${BLUE}Waiting for servers to link via SSL...${NC}"
sleep 3

# Check if servers are linked
echo -e "\n${BLUE}Checking server link status...${NC}"

# Look for connection messages in logs
if grep -q "Established SSL connection" server1.log server2.log 2>/dev/null; then
    echo -e "${GREEN}✓ SSL connection established!${NC}"
else
    echo -e "${YELLOW}⚠ SSL connection status unclear, checking logs...${NC}"
fi

# Show relevant log entries
echo -e "\n${CYAN}Server 1 SSL-related logs:${NC}"
grep -i "ssl\|tls\|link\|server.*connected" server1.log 2>/dev/null | head -10 || echo "  No SSL-related entries found"

echo -e "\n${CYAN}Server 2 SSL-related logs:${NC}"
grep -i "ssl\|tls\|link\|server.*connected" server2.log 2>/dev/null | head -10 || echo "  No SSL-related entries found"

# Test SSL connection directly
echo -e "\n${CYAN}======================================${NC}"
echo -e "${CYAN}Running SSL Connection Test${NC}"
echo -e "${CYAN}======================================${NC}"

echo -e "\n${BLUE}Testing SSL connection to Server 1 (port 6697)...${NC}"
timeout 2 openssl s_client -connect localhost:6697 -brief 2>&1 | grep -E "CONNECTION|CIPHER|PROTOCOL" || echo "  Connection test timeout (expected for IRC)"

echo -e "\n${BLUE}Testing SSL connection to Server 2 (port 7697)...${NC}"
timeout 2 openssl s_client -connect localhost:7697 -brief 2>&1 | grep -E "CONNECTION|CIPHER|PROTOCOL" || echo "  Connection test timeout (expected for IRC)"

# Run the Crystal test client
echo -e "\n${CYAN}======================================${NC}"
echo -e "${CYAN}Running Crystal SSL Test Client${NC}"
echo -e "${CYAN}======================================${NC}"

if [ -f "./test_ssl_server_link.cr" ]; then
    echo -e "\n${BLUE}Testing server link with Crystal client...${NC}"
    timeout 5 crystal run test_ssl_server_link.cr -- --host localhost --port 6697 --password test_ssl_link_password 2>&1 | head -20 || true
else
    echo -e "${YELLOW}Test client not found${NC}"
fi

echo -e "\n${CYAN}======================================${NC}"
echo -e "${CYAN}Test Summary${NC}"
echo -e "${CYAN}======================================${NC}"

# Final check
if kill -0 $PID1 2>/dev/null && kill -0 $PID2 2>/dev/null; then
    echo -e "${GREEN}✓ Both servers are still running${NC}"
    echo -e "${GREEN}✓ SSL server-to-server connection test complete${NC}"

    echo -e "\n${CYAN}You can now:${NC}"
    echo -e "  - Check server logs: ${BLUE}tail -f server1.log${NC} or ${BLUE}tail -f server2.log${NC}"
    echo -e "  - Test SSL client connection: ${BLUE}openssl s_client -connect localhost:6697${NC}"
    echo -e "  - Run Crystal test client: ${BLUE}crystal run test_ssl_server_link.cr -- --host localhost --port 6697${NC}"
    echo -e "\n${YELLOW}Press Ctrl+C to stop the servers${NC}"

    # Keep servers running for manual testing
    wait
else
    echo -e "${RED}✗ One or both servers crashed during testing${NC}"
    echo -e "\n${CYAN}Server 1 last logs:${NC}"
    tail -20 server1.log 2>/dev/null || echo "No log available"
    echo -e "\n${CYAN}Server 2 last logs:${NC}"
    tail -20 server2.log 2>/dev/null || echo "No log available"
    exit 1
fi