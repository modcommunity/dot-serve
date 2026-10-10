# dot-serve

The `dotserve` launcher: a bash script that finds a Godot binary and a project, writes a commented `server.cfg` once, refuses a guessable RCON password, prints the join addresses, and execs a headless dot-server. It is not a Godot project; most family rules about GDScript do not apply. A launcher, not a framework: server behaviour belongs in dot-server.

Read the family [CLAUDE.md](../../CLAUDE.md) for context.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: the four things it gets right, testing without an engine, the systemd unit, what is deliberately not here |
| [docs/history.md](docs/history.md) | editing the script: the two bash traps the self-test caught |

## Layout

| Path | What |
| --- | --- |
| `dotserve` | the launcher (`find_godot`, `check_godot_version`, `ensure_server_cfg`, `check_rcon_password`, `build_command`, `print_service`, `run_with_restart`) |
| `templates/server.cfg` | the commented first-run config; `@RCON_PASSWORD@` is replaced with a generated one |
| `install.sh` | symlinks `dotserve` into `~/.local/bin` (or `$PREFIX`) |
| `tests/selftest.sh` | the suite, with a fake `godot` on `PATH` |

## Running and testing

```bash
bash -n dotserve && bash -n tests/selftest.sh
tests/selftest.sh
```

Exits non-zero on any failure. Run it after any change: two of its checks exist because the obvious bash was wrong in a way that only shows on a fresh install or with an old engine. `--dry-run` and `--print-config` show what a run would do without starting anything.

## Rules that bite

- Print a join address for every transport, LAN included. [design](docs/design.md#the-four-things-it-exists-to-get-right)
- Refuse a known-default or short RCON password; empty means RCON off and is allowed. [design](docs/design.md#the-four-things-it-exists-to-get-right)
- The RCON password never goes on a command line; `server.cfg` is created mode 600 before anything is written. [design](docs/design.md#the-four-things-it-exists-to-get-right)
- Never overwrite an existing `server.cfg`. [design](docs/design.md#the-four-things-it-exists-to-get-right)
- The systemd unit never passes `--restart`; one supervisor, not two. [design](docs/design.md#systemd-one-supervisor-not-two)
- `read_cfg_value` reads one key; do not grow a config parser. [design](docs/design.md#things-deliberately-not-here)
- Under `set -u`, never refer to a `local` declared on the same line. [history](docs/history.md#one-local-line-cannot-use-its-own-earlier-assignment-under-set--u)
- A check that must stop the run is called directly, never inside `$(...)`. [history](docs/history.md#a-check-inside-a-command-substitution-cannot-stop-the-script)

## Open items

- `build_command` passes dot-server settings as `--server-port`, `--server-maxplayers`, `--server-tickrate`, `--server-config-dir`, `--server-hostname`, `--server-tags`, `--server-game`, `--server-websocket`, `--server-ws-port`. `DotServerConfig.cli_prefix()` is `--sv-`, and its keys are `max_players`, `transport_mode` and so on, so these flags do not reach dot-server (an argument without the prefix is not even reported as unknown). The suite cannot see it because it runs a fake engine. Not fixed yet.
- No Windows launcher (`dotserve.ps1` or a `.cmd` shim). The script runs under Git Bash and WSL, which is not the same as supporting Windows.
