# dot-serve design

Why the launcher does what it does, and what it deliberately leaves out. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## A launcher, not a framework

It finds the Godot runtime, picks a config directory, writes a commented `server.cfg` the first time, checks a couple of things that are dangerous to get wrong, prints a join address, and execs the engine ([PLATFORM.md](../../../PLATFORM.md) item 9). Everything else stays in dot-server. If a change here starts looking like server behaviour rather than server *starting*, it is in the wrong repository.

## The four things it exists to get right

1. **Print the join address for every transport, including a LAN one.** "It says it started and my friend cannot connect" is almost always a bind address or a firewall.
2. **Refuse a default RCON password.** A generated one printed once beats a documented default nobody changes. `check_rcon_password` refuses the known defaults (`WEAK_RCON_PASSWORDS`) and anything shorter than 8 characters. Empty is *not* refused: it means the RCON listener does not open at all, which is right for a server nobody administers remotely.
3. **Never put the RCON password on a command line.** argv is readable by every other process on the machine and ends up in pasted bug reports: the same reason `DotConfig.sensitive_keys` refuses secrets from argv and the environment. It lives in `server.cfg`, which is created under `umask 077` *before* anything is written into it, then `chmod 600`.
4. **Never overwrite `server.cfg`.** An operator's edits are the configuration. Regenerating on upgrade throws them away on the one run nobody is watching.

## Testing a launcher without launching anything

`--dry-run` prints the exact command it would run and exits. `--print-config` prints the resolved configuration and exits. Both exist so the interesting part is checkable, and a fake `godot` on `PATH` covers the rest: the suite runs on a machine with no engine installed at all.

That means the one thing **not** covered is whether dot-server actually accepts the argv `build_command` produces. That was meant to be checked by reading against `DotServerConfig`, and the reading was wrong: see the open item in [CLAUDE.md](../CLAUDE.md#open-items).

## systemd: one supervisor, not two

`--install-service NAME` prints a unit. It sets `Restart=on-failure` and deliberately does **not** pass `--restart`. dotserve has its own exponential backoff, and two supervisors backing off against each other produce a restart storm that reads as a crash loop.

`RestartPreventExitStatus` lists the misconfiguration codes (`EXIT_NO_GODOT`, `EXIT_NO_PROJECT`, `EXIT_CONFIG`, `EXIT_PORT`). A server that cannot find its project will not find it on the ninetieth attempt either, and retrying turns one clear error into a journal full of them.

`ProtectSystem=strict` with `ReadWritePaths` limited to the config and log directories: a game server is exactly the kind of process that should not be able to write anywhere else.

## Things deliberately not here

- **Downloading Godot.** It finds one; it does not fetch one. A launcher that downloads a binary is a launcher that has to verify a signature, and that is a different program with different risks.
- **Reading `server.cfg` for anything but `rcon_password`.** `read_cfg_value` is deliberately a one-key `sed` and not a config parser. dot-server's console is the parser, and a second one here would drift from it.
- **Server listing registration.** Announcing a server to the backbone is dot-auth's `DotBackboneClient` and a running server's job, not a launcher's.
- **Multi-instance management.** One invocation, one server. Running four is four systemd units with four `--config` directories, which is what `--install-service NAME` is for.
- **Log rotation.** `--log` names a directory and the server writes into it. Rotation is `logrotate`'s job and doing it badly here would fight it.
