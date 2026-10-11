# dot-serve history

Two bash traps, both found by the self-test. The rules they left are in [CLAUDE.md](../CLAUDE.md).

## One `local` line cannot use its own earlier assignment under `set -u`

`local a="$1" b="$a/x"`: bash expands every word of a `local` command before it assigns any of them, so `$a` is not yet set when `"$a/x"` is expanded. It failed in `ensure_server_cfg`, which is the *first run of a fresh install*: the single most important path in the whole script.

## A check inside a command substitution cannot stop the script

`V="$(check_version)"`: `die` inside a command substitution exits the subshell and nothing else, and a `|| true` swallowed the status on top of that. The Godot version gate printed its refusal and then used the old binary anyway. `check_godot_version` now sets a global (`GODOT_VERSION`) and is called directly. The self-test asserts not just that the message appears but that *the run stops*, which is what caught it.

## Every server flag did nothing (fixed 2026-10-10)

`build_command` passed `--server-port`, `--server-maxplayers`, `--server-tickrate` and six more for as long as dotserve existed. `DotServerConfig.cli_prefix()` has always been `--sv-`, its keys are `max_players` and `transport_mode`, and dot-core's `DotConfig.apply_cli` skips an argument without the prefix without even an unknown-key warning, so every dotserve server ran on dot-server's defaults whatever the operator typed. The self-test passed throughout because it ran a fake engine and checked only that the numbers appeared somewhere in the command line. Found by the documentation pass, which grepped the claim; fixed by spelling the keys as dot-server does, passing the game as `+changegame`, and checking flag and value together. Browsers now share the game port (the dual transport), so `--ws-port` is accepted and ignored.
