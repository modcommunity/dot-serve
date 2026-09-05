# dot-serve

The `dotserve` launcher. Read `../../CLAUDE.md` for the family-wide context; this is
the only project in it that is not a Godot addon, so most of those rules do not apply.

## What this is, and what it is not

PLATFORM.md item 9. **A launcher, not a framework.** It finds the Godot runtime, picks
a config directory, writes a commented `server.cfg` the first time, checks a couple of
things that are dangerous to get wrong, prints a join address, and execs the engine.

Everything else stays in dot-server, where it belongs. If a change here starts looking
like server behaviour rather than server *starting*, it is in the wrong repository.

## The four things it exists to get right

1. **Print the join address for every transport, including a LAN one.** "It says it
   started and my friend cannot connect" is almost always a bind address or a firewall.
2. **Refuse a default RCON password.** A generated one printed once beats a documented
   default nobody changes. Empty is *not* refused — it means the RCON listener does not
   open at all, which is right for a server nobody administers remotely.
3. **Never put the RCON password on a command line.** argv is readable by every other
   process on the machine and ends up in pasted bug reports — the same reason
   `DotConfig.sensitive_keys` refuses secrets from argv and the environment. It lives
   in `server.cfg`, which is created mode 600 *before* anything is written into it.
4. **Never overwrite `server.cfg`.** An operator's edits are the configuration.
   Regenerating on upgrade throws them away on the one run nobody is watching.

## Bash traps this hit, both found by the self-test

**`local a="$1" b="$a/x"` is an unbound variable under `set -u`.** Bash expands every
word of a `local` command before it assigns any of them, so `$a` is not yet set when
`"$a/x"` is expanded. It failed in `ensure_server_cfg`, which is the *first run of a
fresh install* — the single most important path in the whole script.

**`V="$(check_version)"` cannot fail the script.** `die` inside a command substitution
exits the subshell and nothing else, and the `|| true` swallowed the status on top of
that. The Godot version gate printed its refusal and then used the old binary anyway.
It now sets a global and is called directly. The self-test asserts not just that the
message appears but that *the run stops*, which is what caught it.

## Testing a launcher without launching anything

`--dry-run` prints the exact command it would run and exits. `--print-config` prints
the resolved configuration and exits. Both exist so the interesting part is checkable,
and a fake `godot` on `PATH` covers the rest — the suite runs on a machine with no
engine installed at all.

That means the one thing **not** covered is whether dot-server actually accepts the
argv `build_command` produces. Those flags follow `DotServerConfig`'s
`--server-` CLI prefix and are checked against it by reading, not by running.

## systemd: one supervisor, not two

The generated unit sets `Restart=on-failure` and deliberately does **not** pass
`--restart`. dotserve has its own exponential backoff, and two supervisors backing off
against each other produce a restart storm that reads as a crash loop.

`RestartPreventExitStatus` lists the misconfiguration codes. A server that cannot find
its project will not find it on the ninetieth attempt either, and retrying turns one
clear error into a journal full of them.

`ProtectSystem=strict` with `ReadWritePaths` limited to the config and log directories:
a game server is exactly the kind of process that should not be able to write anywhere
else.

## Validating changes

```bash
cd godot/dot-serve
bash -n dotserve && bash -n tests/selftest.sh
tests/selftest.sh
```

54 checks. Exits non-zero on any failure.

**Run it after any change.** Two of the checks exist because the obvious bash was
wrong in a way that only shows on a fresh install or with an old engine — neither of
which anyone reproduces by hand.

## Things deliberately not here

- **Downloading Godot.** It finds one; it does not fetch one. A launcher that
  downloads a binary is a launcher that has to verify a signature, and that is a
  different program with different risks.
- **A Windows version.** `dotserve.ps1` or a `.cmd` shim is a real gap. The bash script
  runs under Git Bash and WSL today, which is not the same as supporting Windows.
- **Reading `server.cfg` for anything but `rcon_password`.** `read_cfg_value` is
  deliberately a one-key `sed` and not a config parser. dot-server's console is the
  parser, and a second one here would drift from it.
- **Server listing registration.** Announcing a server to the backbone is dot-auth's
  `DotBackboneClient` and a running server's job, not a launcher's.
- **Multi-instance management.** One invocation, one server. Running four is four
  systemd units with four `--config` directories, which is what `--install-service NAME`
  is for.
- **Log rotation.** `--log` names a directory and the server writes into it. Rotation is
  `logrotate`'s job and doing it badly here would fight it.
