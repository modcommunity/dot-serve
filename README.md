This is the **launcher** for TMC's **Dot** dedicated server. The server is deeply configurable and had no front door, so this is the doorbell.

The **Dot** collection is a set of open source Godot 4 assets that provide modular building blocks for games and applications in the TMC ecosystem, covering core functionality, networking, authentication, cloud integration, and more. This is the shell script that starts one of them, so it is not a Godot project itself and needs nothing installed to run.

**This tool and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This tool, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Starting a Server Without Knowing How It Works
`dotserve` — start a [dot-server](../dot-server) without knowing how dot-server works.

dot-server is deeply configurable: cvars, flags, `server.cfg`, `autoexec.cfg`,
`+command` arguments, RCON, and layered configuration from file, environment and argv.
What it did not have was a front door. This is the doorbell.

Part of the [dot-*](../NOTES.md) family, and the only piece that is not a Godot addon.
Needs `bash` and a Godot 4.4+ binary.

## Install

```bash
./install.sh                 # symlinks into ~/.local/bin
PREFIX=/usr/local/bin sudo ./install.sh
```

## Use

```bash
dotserve                            # sensible defaults, prints a join address
dotserve --game res://games/arena   # a specific game
dotserve --port 27015 --web         # also listen for browser clients
dotserve --restart                  # come back up after a crash
dotserve -- +sv_cheats 1 +map dm_arena
```

The first run writes a commented `server.cfg` under `~/.config/dotserve`, generates an
RCON password, and prints it once. Every run after that reads the file and never
touches it.

## What it does that is easy to leave out

**It prints the address a friend can paste**, including a LAN address — because "it
says it started and my friend cannot connect" is almost always a bind address or a
firewall, and the first thing that helps is knowing which address the server is
actually on.

**It refuses to start with a guessable RCON password.** An empty one is fine and means
the RCON listener does not open at all. What is refused is a placeholder that got
shipped, copied out of a forum post, or left in a template.

**The RCON password is never on a command line.** `server.cfg` is written mode 600
before anything goes into it. argv and the environment are readable by every other
process on the machine and both end up in pasted bug reports — the same reason
`DotConfig.sensitive_keys` refuses secrets from them.

**It never overwrites your `server.cfg`.** Your edits *are* the server's configuration.

## Options

Run `dotserve --help`. The ones worth knowing:

| | |
| --- | --- |
| `--dry-run` | Print the command it would run, and exit. |
| `--print-config` | Print the resolved configuration, and exit. |
| `--install-service [NAME]` | Print a systemd unit for this invocation. |
| `--restart` | Restart on a crash, with exponential backoff to a 60-second cap. |
| `--web` / `--ws-port N` | Also listen for browser clients. Defaults to `--port` + 1. |

Exit codes are meaningful, so a supervisor can tell a misconfiguration from a crash:
`2` usage, `3` no Godot, `4` no project, `5` bad config, `6` port in use. The generated
systemd unit lists all of them under `RestartPreventExitStatus`.

## Validating

```bash
tests/selftest.sh
```

54 checks. Nothing starts a real server — the launcher's whole job is what happens
*before* one does, and `--dry-run` and `--print-config` exist so that is checkable. A
fake `godot` on `PATH` stands in for the engine, so the suite runs on a machine that
has none.
