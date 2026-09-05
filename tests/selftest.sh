#!/usr/bin/env bash
#
# dotserve self-test.
#
#   tests/selftest.sh
#
# Exits non-zero on any failure, so it works as a smoke test as-is.
#
# Nothing here starts a real server: the launcher's whole job is everything that
# happens *before* the server starts, and --dry-run and --print-config exist so that
# part is checkable without one. A fake `godot` on PATH stands in for the engine, so
# the test runs on a machine that has none.
#
# The cases that matter most are the ones where a mistake is a security problem rather
# than an inconvenience: an RCON password anyone could guess, a config file every user
# on the machine can read, and a generated config that overwrites an operator's edits.

set -uo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DOTSERVE="$ROOT/dotserve"
readonly TMP="$ROOT/tests/tmp"

PASSED=0
FAILED=0
FAILURES=()

check() {
  local condition="$1" what="$2" detail="${3:-}"

  if [ "$condition" = "1" ]; then
    PASSED=$((PASSED + 1))
    printf '  ok    %s\n' "$what"
  else
    FAILED=$((FAILED + 1))
    FAILURES+=("$what${detail:+ — $detail}")
    printf '  FAIL  %s%s\n' "$what" "${detail:+ — $detail}"
  fi
}

check_contains() {
  local haystack="$1" needle="$2" what="$3"
  case "$haystack" in
    *"$needle"*) check 1 "$what" ;;
    *)           check 0 "$what" "expected to find '$needle'" ;;
  esac
}

check_missing() {
  local haystack="$1" needle="$2" what="$3"
  case "$haystack" in
    *"$needle"*) check 0 "$what" "unexpectedly found '$needle'" ;;
    *)           check 1 "$what" ;;
  esac
}

group() { printf '\n%s\n' "$1"; }

# --- Fixtures ---------------------------------------------------------------

setup() {
  rm -rf "$TMP"
  mkdir -p "$TMP/bin" "$TMP/project" "$TMP/project/sub/deeper" "$TMP/config" "$TMP/logs"

  cat > "$TMP/project/project.godot" <<'PROJECT'
config_version=5

[application]
config/name="test-project"
PROJECT

  # A fake Godot: reports a modern version, records how it was called, exits 0.
  cat > "$TMP/bin/godot" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "4.4.1.stable.official.49a5bc7b6"
  exit 0
fi
printf '%s\n' "$@" > "${DOTSERVE_TEST_ARGS:-/dev/null}"
exit "${DOTSERVE_FAKE_EXIT:-0}"
FAKE
  chmod +x "$TMP/bin/godot"

  # An old one, for the version gate.
  cat > "$TMP/bin/godot-old" <<'OLD'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "4.2.2.stable.official"
  exit 0
fi
exit 0
OLD
  chmod +x "$TMP/bin/godot-old"

  export PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

run_dotserve() {
  "$DOTSERVE" --godot "$TMP/bin/godot" --project "$TMP/project" "$@" 2>&1
}

# --- Discovery --------------------------------------------------------------

test_project_discovery() {
  group "finding the project"

  local out
  out="$(cd "$TMP/project/sub/deeper" && "$DOTSERVE" --godot "$TMP/bin/godot" \
    --config "$TMP/config" --print-config 2>&1)"
  check_contains "$out" "$TMP/project" \
    "a project is found by walking up from a subdirectory"

  out="$("$DOTSERVE" --godot "$TMP/bin/godot" --project "$TMP/logs" \
    --config "$TMP/config" --print-config 2>&1)"
  local status=$?
  check_contains "$out" "no project.godot" \
    "a directory with no project.godot is refused"

  out="$(cd / && "$DOTSERVE" --godot "$TMP/bin/godot" --config "$TMP/config" \
    --print-config 2>&1)"
  check_contains "$out" "no project.godot" \
    "and so is running from somewhere with no project above it"
}

test_godot_discovery() {
  group "finding Godot"

  local out
  out="$(GODOT="$TMP/bin/godot" "$DOTSERVE" --project "$TMP/project" \
    --config "$TMP/config" --print-config 2>&1)"
  check_contains "$out" "4.4.1" "\$GODOT is used when it is set"

  out="$("$DOTSERVE" --godot "$TMP/bin/godot-old" --project "$TMP/project" \
    --config "$TMP/config" --print-config 2>&1)"
  check_contains "$out" "4.4 or newer" \
    "an old Godot is refused with a version message"
  check_missing "$out" "project      " \
    "and the run stops rather than continuing"

  out="$("$DOTSERVE" --godot "$TMP/bin/nonexistent" --project "$TMP/project" \
    --print-config 2>&1)"
  check_contains "$out" "not executable" "a --godot that is not there is refused"
}

# --- Configuration ----------------------------------------------------------

test_first_run() {
  group "first run"

  local dir="$TMP/first"
  rm -rf "$dir"

  local out
  out="$(run_dotserve --config "$dir" --dry-run)"

  check "$([ -f "$dir/server.cfg" ] && echo 1 || echo 0)" \
    "a server.cfg is written on first run"
  check_contains "$out" "RCON password is" \
    "and its RCON password is printed once"

  local mode
  mode="$(stat -c '%a' "$dir/server.cfg" 2>/dev/null || stat -f '%Lp' "$dir/server.cfg")"
  check "$([ "$mode" = "600" ] && echo 1 || echo 0)" \
    "readable only by its owner, because it holds the RCON password" \
    "mode $mode"

  local password
  password="$(sed -n 's/^rcon_password "\(.*\)"$/\1/p' "$dir/server.cfg")"
  check "$([ "${#password}" -ge 16 ] && echo 1 || echo 0)" \
    "the generated password is long" "${#password} characters"
  check "$([ "$password" != "@RCON_PASSWORD@" ] && echo 1 || echo 0)" \
    "and the template placeholder was actually substituted"

  # Never overwriting is the whole contract: an operator's edits ARE the server's
  # configuration, and regenerating on upgrade throws them away on the one run
  # nobody is watching.
  printf '\n// operator edit\nsv_gravity 800\n' >> "$dir/server.cfg"
  out="$(run_dotserve --config "$dir" --dry-run)"
  check_contains "$(cat "$dir/server.cfg")" "operator edit" \
    "a second run does not overwrite it"
  check_missing "$out" "RCON password is" \
    "and does not print the password again"

  local second
  second="$(sed -n 's/^rcon_password "\(.*\)"$/\1/p' "$dir/server.cfg")"
  check "$([ "$password" = "$second" ] && echo 1 || echo 0)" \
    "and the password is unchanged"
}

test_rcon_refusal() {
  group "refusing a guessable RCON password"

  local dir="$TMP/weak"
  local weak out status

  for weak in changeme password admin dotserve "@RCON_PASSWORD@"; do
    rm -rf "$dir"; mkdir -p "$dir"
    printf 'hostname "x"\nrcon_password "%s"\n' "$weak" > "$dir/server.cfg"

    out="$(run_dotserve --config "$dir" --dry-run 2>&1)"
    status=$?

    check "$([ "$status" -ne 0 ] && echo 1 || echo 0)" \
      "'$weak' is refused" "exit $status"
  done

  # Empty is not weak. It means the RCON listener does not open at all, which is the
  # right setting for a server nobody administers remotely.
  rm -rf "$dir"; mkdir -p "$dir"
  printf 'hostname "x"\nrcon_password ""\n' > "$dir/server.cfg"
  out="$(run_dotserve --config "$dir" --dry-run 2>&1)"
  status=$?
  check "$([ "$status" -eq 0 ] && echo 1 || echo 0)" \
    "an empty password is accepted, and means RCON is off" "exit $status"
  check_contains "$out" "RCON is off" "and says so"

  rm -rf "$dir"; mkdir -p "$dir"
  printf 'rcon_password "abc"\n' > "$dir/server.cfg"
  out="$(run_dotserve --config "$dir" --dry-run 2>&1)"
  status=$?
  check "$([ "$status" -ne 0 ] && echo 1 || echo 0)" \
    "and a short one is refused too" "exit $status"

  rm -rf "$dir"; mkdir -p "$dir"
  printf 'rcon_password "a-genuinely-long-one"\n' > "$dir/server.cfg"
  status=0
  run_dotserve --config "$dir" --dry-run >/dev/null 2>&1 || status=$?
  check "$([ "$status" -eq 0 ] && echo 1 || echo 0)" \
    "while a real password is accepted" "exit $status"
}

# --- Arguments --------------------------------------------------------------

test_argument_validation() {
  group "argument validation"

  local out status

  for bad in "--port 0" "--port 99999" "--port abc" "--maxplayers 0" "--tickrate 999"; do
    status=0
    out="$(run_dotserve --config "$TMP/config" $bad --dry-run 2>&1)" || status=$?
    check "$([ "$status" -ne 0 ] && echo 1 || echo 0)" \
      "'$bad' is refused" "exit $status"
  done

  status=0
  out="$(run_dotserve --config "$TMP/config" --nonsense --dry-run 2>&1)" || status=$?
  check "$([ "$status" -ne 0 ] && echo 1 || echo 0)" \
    "an unknown option is refused rather than ignored" "exit $status"

  # The same port twice would bind one listener and silently not the other, which
  # reads as "browser clients cannot connect" with nothing in the log.
  status=0
  out="$(run_dotserve --config "$TMP/config" --port 27015 --ws-port 27015 \
    --dry-run 2>&1)" || status=$?
  check "$([ "$status" -ne 0 ] && echo 1 || echo 0)" \
    "the same port for UDP and WebSocket is refused" "exit $status"
}

test_command_building() {
  group "the command it builds"

  # A warm-up run so the config already exists: otherwise the run under test also
  # prints the one-time creation notice, and the password check below would find the
  # password there rather than on the command line it is actually about.
  run_dotserve --config "$TMP/config" --dry-run >/dev/null 2>&1

  local out
  out="$(run_dotserve --config "$TMP/config" --port 27044 --maxplayers 24 \
    --tickrate 128 --name "Test Server" --game "res://games/arena" --dry-run)"

  check_contains "$out" "--headless" "the server runs headless"
  check_contains "$out" "$TMP/project" "in the right project"
  check_contains "$out" "27044" "on the right port"
  check_contains "$out" "24" "with the right player count"
  check_contains "$out" "128" "and the right tick rate"
  check_contains "$out" "res://games/arena" "loading the right game"

  # The RCON password must never reach a command line: argv is readable by every
  # other process on the machine, and it ends up in pasted bug reports. dot-server's
  # own DotConfig refuses secrets from argv for the same reason.
  local password
  password="$(sed -n 's/^rcon_password "\(.*\)"$/\1/p' "$TMP/config/server.cfg" || true)"
  if [ -n "$password" ]; then
    check_missing "$out" "$password" \
      "and the RCON password is not on the command line"
  fi

  out="$(run_dotserve --config "$TMP/config" --web --port 27015 --dry-run)"
  check_contains "$out" "27016" \
    "--web defaults the WebSocket port to one above the UDP one"
  check_contains "$out" "websocket" "and turns the WebSocket listener on"

  out="$(run_dotserve --config "$TMP/config" --dry-run -- +sv_cheats 1 +map dm_arena)"
  check_contains "$out" "+sv_cheats" "commands after -- are passed through"
  check_contains "$out" "+map" "all of them"

  out="$(run_dotserve --config "$TMP/config" --dry-run +exec autoexec.cfg)"
  check_contains "$out" "+exec" "and a bare +command is too"
}

test_service_unit() {
  group "systemd unit"

  local out
  out="$(run_dotserve --config "$TMP/config" --log "$TMP/logs" --port 27099 \
    --install-service 2>&1)"

  check_contains "$out" "[Service]" "a unit is printed"
  check_contains "$out" "ExecStart=" "with an ExecStart"
  check_contains "$out" "27099" "carrying the port it was invoked with"
  check_contains "$out" "RestartPreventExitStatus" \
    "and refusing to retry a misconfiguration"
  check_contains "$out" "ReadWritePaths=$TMP/config" \
    "with the config directory writable and the rest of the filesystem not"

  # dotserve has its own backoff. Two supervisors backing off against each other
  # produce a restart storm that looks like a crash loop.
  check_missing "$out" "--restart" \
    "and it does not also ask dotserve to supervise itself"
}

test_output_hygiene() {
  group "output"

  local out
  out="$(run_dotserve --config "$TMP/config" --quiet --dry-run)"
  check_missing "$out" "Players on this machine" "--quiet suppresses the banner"

  out="$(NO_COLOR=1 run_dotserve --config "$TMP/config" --print-config)"
  check_missing "$out" $'\033' "NO_COLOR removes escape sequences"

  out="$("$DOTSERVE" --version)"
  check_contains "$out" "dotserve" "--version prints a version"

  out="$("$DOTSERVE" --help)"
  check_contains "$out" "--install-service" "--help documents every option"
  check_contains "$out" "--dry-run" "including the ones a test depends on"
}

# --- Run --------------------------------------------------------------------

printf 'dotserve self-test\n'

setup
trap teardown EXIT

test_project_discovery
test_godot_discovery
test_first_run
test_rcon_refusal
test_argument_validation
test_command_building
test_service_unit
test_output_hygiene

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"

for failure in "${FAILURES[@]:-}"; do
  [ -n "$failure" ] && printf '  FAIL  %s\n' "$failure"
done

[ "$FAILED" -eq 0 ] || exit 1
