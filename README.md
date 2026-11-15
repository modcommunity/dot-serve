`dotserve` starts a [dot-server](https://github.com/gamespice-platform/server) for you without you needing to know how dot-server works. It is a shell script, not a Godot addon. It needs `bash` and a Godot 4.7+ binary.

dot-server is very configurable (cvars, flags, `server.cfg`, `autoexec.cfg`, `+command` arguments, RCON, layered config from file, environment and command line). `dotserve` is the easy way in.

## Install

```bash
./install.sh                         # symlinks into ~/.local/bin
PREFIX=/usr/local/bin sudo ./install.sh
```

## Use

```bash
dotserve                             # sensible defaults, prints a join address
dotserve --game res://games/fc       # a specific game
dotserve --port 27015 --web          # also listen for browser clients
dotserve --restart                   # come back up after a crash
dotserve -- +sv_cheats 1 +map dm_box # pass cvars and commands to the server
```

The first run writes a commented `server.cfg` under `~/.config/dotserve`, generates an RCON password and prints it once. Later runs read the file and never touch it.

## What it does for you

| Behaviour | Why |
| --- | --- |
| Prints the address a friend can paste, including a LAN address | "It started but my friend cannot connect" is nearly always a bind address or firewall, and knowing which address the server is on is the first step. |
| Refuses a guessable RCON password | An empty one is fine and means RCON does not listen at all. A placeholder copied from a template or forum post is refused. |
| Never puts the RCON password on a command line | `server.cfg` is written mode 600 first. Command lines and the environment are readable by other processes and end up in bug reports. |
| Never overwrites `server.cfg` | Your edits are the server's configuration. |

## Options

Run `dotserve --help` for all of them. The ones worth knowing:

| Option | Does |
| --- | --- |
| `--dry-run` | Print the command it would run, and exit. |
| `--print-config` | Print the resolved configuration, and exit. |
| `--install-service [NAME]` | Print a systemd unit for this invocation. |
| `--restart` | Restart after a crash, with a growing delay that tops out at 60 seconds. |
| `--web` | Also serve browser clients, over WebSocket on the game port. |

Exit codes tell a supervisor a misconfiguration from a crash:

| Code | Meaning |
| --- | --- |
| 2 | Usage error |
| 3 | No Godot found |
| 4 | No project found |
| 5 | Bad config |
| 6 | Port in use |

The generated systemd unit lists them under `RestartPreventExitStatus`.

## Testing

Run `tests/selftest.sh`. It does not start a real server: a fake `godot` on `PATH` stands in for the engine, so it runs on a machine that has none.

## Licence

MIT, see [LICENSE](LICENSE). Part of the TMC [dot-*](https://github.com/gamespice-platform) family of tools. Written with Claude Code and maintained by `gamemann`. It has its own test suite, but little of it has been used by real users yet, so please [open an issue](https://github.com/gamespice-platform/serve/issues) when you hit a rough edge.
