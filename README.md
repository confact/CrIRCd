# CrIRCd - IRCD (deamon) in Crystal

This is an crystal IRC server made to follow the spec over time. Right now it is not 100% supporting the spec and is not recommended for production.

## What you can do now:
* let user connect
* Send MOTD and stats to the user
* PING/PONG with disconnection after 3 unanswered PINGS.
* send Peer to peer message between users.
* channels
* send messages in channels
* Kick user from channel
* invite user to channel
* set topic in channel
* make channel private
* set password on channel
* set limit on channel
* set channel as secret
* able to list channels
* ban user from channel

## Plan to have:
* chan modes
* User modes
* GLines support
* Resolve ip address and lookup for bans
* Server OPs
* SSL TLS support
* NickServ
* ChanServ
* Server-to-server communication


## How to run
Would need crystal >= 1.4 to build this server.

1. clone this repo
2. build the program with: `crystal build --release ./src/circed.cr`
3. run the program with `./circed` 

### Config
The config is in `config.yml` and is pretty self explanatory. You can change the port, hostname, stats and other things.

## Known issues
* modes is not there for users, channels
* can't be op of channels.
* NAMES list of users in channel is not working correctly
* Some things like NICK change won't update users in channels of the change yet
* socket errors
* timeout errors

## Contributions
Everyone is welcome to contribute. Fork this repo, make your changes and make a Pull Request explaining what you did and why. And I and others will review it and merge it if it make sense. :)

## Maintainers:
* Håkan Nylén - @confact
