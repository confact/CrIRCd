# Circed - IRCD (deamon) in Crystal

This is an crystal IRC server made to follow the spec over time. Right now it is not 100% supporting the spec and is not recommended for production.

## What you can do now:
* let user connect
* Send MOTD and stats to the user
* PING/PONG with disconnection after 10 unanswered PINGS.
* send Peer to peer message between users.

## Plan to have:
* Channels
* chan modes
* User modes
* GLines support
* Resolve ip address and lookup for bans
* Server OPs
* SSL TLS support
* NickServ
* ChanServ
* Server-to-server communication
* Simple config in YML


## How to run
Would need crystal >= 1.0 to build this server.

1. clone this repo
2. build the program with: `crystal build --release ./src/circed.cr`
3. run the program with `./circed` 

## Known issues
* Ping/pong is acting weird, and is not stopping sometimes pinging even if the client have closed the socket.

## Contributions
Everyone is welcome to contribute. Fork this repo, make your changes and make a Pull Request explaining what you did and why. And I and others will review it and merge it if it make sense. :)

## Maintainers:
* Håkan Nylén - @confact
