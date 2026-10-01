#!/usr/bin/env bash
# =============================================================================
# setup.sh - one-command setup for the JasaSane membership app
#
#   backend  : Node.js + Express + PostgreSQL  ->  http://localhost:5000
#   frontend : React 18 (Create React App)      ->  http://localhost:3000
#
# This script only prepares the machine: prerequisites, database, backend/.env
# and dependencies. It starts nothing. Pass --start to launch both servers.
#
# Platforms : macOS, Ubuntu/Debian, other Linux, WSL, Git Bash on Windows.
#             Native Windows PowerShell users should run setup.ps1 instead
#             (identical flags and behaviour).
#
# Usage     : ./setup.sh --help
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Paths (resolved from this script's location, not the caller's cwd)
# -----------------------------------------------------------------------------
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"

BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"
LOG_DIR="$ROOT/logs"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"
BACKEND_PID="$LOG_DIR/backend.pid"
FRONTEND_PID="$LOG_DIR/frontend.pid"

MIN_NODE_MAJOR=18
MIN_PG_MAJOR=14

# -----------------------------------------------------------------------------
# Defaults (overridable by flags / environment)
# -----------------------------------------------------------------------------
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
JWT_SECRET="${JWT_SECRET:-}"
API_PORT=5000
FRONTEND_PORT=3000

ASSUME_YES=0
DO_SEED=0
DO_START=0
RUN_DEV=0
TRUST_LOCAL_AUTH=0
# Check for / install the OpenCode CLI. Off by default: it is a global npm install
# that the app itself does not need, so it happens only when asked for.
OPEN_CODE=0
MODE="setup"

# Toolchain state, decided once in check_prereqs and read by every step that
# shells out to node/npm. A missing Node must never abort the run - it only
# means the npm steps cannot be performed, so those are skipped and recorded
# here rather than guessed at. Mirrors $script:NodeReady / $script:NpmReady in
# setup.ps1.
NODE_READY=1
NPM_READY=1

# Steps that could not run, for the SETUP INCOMPLETE report at the end. Two
# parallel plain arrays rather than one string or a map: bash 3.2 (Git Bash on
# macOS) has no associative arrays, and a delimiter-joined string would break on
# a reason that itself contains the delimiter. Port of $script:Skipped /
# Add-SkippedStep in setup.ps1.
SKIPPED_STEP=()
SKIPPED_REASON=()

add_skipped_step() {
  # add_skipped_step <step> <reason>
  SKIPPED_STEP+=("$1")
  SKIPPED_REASON+=("$2")
}

has_skipped_steps() {
  [ "${#SKIPPED_STEP[@]}" -gt 0 ]
}

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

step()  { printf '\n%s==> %s%s\n' "$C_BLUE$C_BOLD" "$*" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '    %s[!]%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '    %s[!!]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
# Notes are advisory and go to stdout so they interleave with the log stream.
note()  { printf '    %s[-]%s  %s\n' "$C_BLUE" "$C_RESET" "$*"; }

# Never leave the terminal without echo after a hidden password prompt.
trap 'stty echo 2>/dev/null' EXIT INT TERM

# -----------------------------------------------------------------------------
# Interactive helpers
# -----------------------------------------------------------------------------
have_tty() { [ -t 0 ]; }

confirm() {
  # confirm <question> [y|n]
  local question="$1" default="${2:-y}" reply
  if [ "$ASSUME_YES" = "1" ]; then
    info "$question -> yes (--yes)"
    return 0
  fi
  if ! have_tty; then
    err "No terminal available for confirmation: $question"
    err "Re-run with --yes, or pass the relevant flag to run non-interactively."
    return 1
  fi
  printf '    %s? %s [%s] %s' "$C_BOLD" "$question" "$default" "$C_RESET" >&2
  if ! IFS= read -r reply; then
    printf '\n' >&2
    return 1
  fi
  reply="${reply:-$default}"
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *)                 return 1 ;;
  esac
}

confirm_typed() {
  # confirm_typed <question> <exact word to type>
  local question="$1" expected="$2" reply
  if [ "$ASSUME_YES" = "1" ]; then
    info "$question -> confirmed (--yes)"
    return 0
  fi
  if ! have_tty; then
    err "No terminal available to confirm: $question"
    err "Re-run with --yes if you accept the consequences."
    return 1
  fi
  printf '    %s? %s\n      Type %s%s%s to continue: %s' \
    "$C_BOLD" "$question" "$C_BOLD$C_YELLOW" "$expected" "$C_RESET" "$C_RESET" >&2
  if ! IFS= read -r reply; then
    printf '\n' >&2
    return 1
  fi
  printf '\n' >&2
  [ "$reply" = "$expected" ]
}

prompt() {
  # prompt <varname> <message> [default]
  local __var="$1" __msg="$2" __default="${3:-}" __reply=''
  have_tty || die "'$__msg' needs an answer: re-run with the matching --flag (see --help)."
  if [ -n "$__default" ]; then
    printf '    %s: %s' "$__msg" "$C_BOLD" >&2
    printf '[%s] ' "$__default" >&2
  else
    printf '    %s: ' "$__msg" >&2
  fi
  IFS= read -r __reply || die "Failed to read input for '$__msg'."
  [ -z "$__reply" ] && [ -n "$__default" ] && __reply="$__default"
  printf -v "$__var" '%s' "$__reply"
}

prompt_secret() {
  # prompt_secret <varname> <message>  -- input is not echoed
  local __var="$1" __msg="$2" __reply=''
  have_tty || die "'$__msg' needs an answer: re-run with --db-password (see --help)."
  printf '    %s: ' "$__msg" >&2
  stty -echo 2>/dev/null
  IFS= read -r __reply
  local rc=$?
  stty echo 2>/dev/null
  printf '\n' >&2
  [ $rc -eq 0 ] || die "Failed to read '$__msg'."
  printf -v "$__var" '%s' "$__reply"
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
setup.sh - one-command setup for the membership app (backend + frontend)

  Prerequisites: Node.js 18+, npm, PostgreSQL 14+ (running on port 5432).
  If anything is missing the script prints the exact install command for your
  platform and asks before running it. Nothing is installed without consent.

MODES
  ./setup.sh                      Set up everything. Starts nothing.
  ./setup.sh --start              Also start backend + frontend in the background
  ./setup.sh --seed               Also seed demo data (DESTRUCTIVE, confirms)
  ./setup.sh --status             Report what is currently running
  ./setup.sh --stop               Stop backend + frontend
  ./setup.sh --logs               Tail both logs (Ctrl+C to stop tailing)
  ./setup.sh --clean              Stop and remove node_modules + logs

DATABASE
  --db-name=NAME        Database to create/use        (default: jasasane_app)
  --db-user=USER        PostgreSQL user               (default: prompt)
  --db-password=PASS    PostgreSQL password           (default: prompt, hidden)
  --db-host=HOST        PostgreSQL host               (default: localhost)
  --db-port=PORT        PostgreSQL port               (default: 5432)
  --trust-local-auth    Skip the password prompt and the credential check.
                        Use only when pg_hba.conf trusts local connections
                        ('trust' or 'peer'). DB_PASSWORD is left empty.

PORTS
  --port=PORT           Backend port                  (default: 5000)
  --frontend-port=PORT  Frontend port                 (default: 3000)
  Note: frontend/src/services/api.js hardcodes http://localhost:5000, so
  changing --port also requires editing that file.

OTHER
  --opencode            Check the OpenCode CLI: print its version when it is
                          installed, or offer to install opencode-ai@latest
                          globally via npm when it is not. Also writes
                          opencode.json if that file does not exist. Nothing is
                          installed without confirmation.
  --dev                 Run the backend with nodemon in the foreground
                        (implies --start, but the frontend stays stopped)
  --yes, -y             Assume yes for every prompt (non-interactive use)
  --help, -h            This message

ENVIRONMENT EQUIVALENTS
  DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, JWT_SECRET

NOTES
  * This script sets up the machine and stops there. It starts nothing unless
    you pass --start or --dev.
  * Tables (users, otps, records) are created automatically by the backend on
    first boot, not by this script. Run the backend once and they appear.
  * The seed script DELETES every row in records and otps, and every user whose
    phone is not 09999999999 / 09111111111 / 09222222222. It never runs unless
    you pass --seed.
  * OTPs are simulated: they are printed to the backend console and nowhere
    else. They are written to logs/backend.log when run in the background.
USAGE
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)      usage; exit 0 ;;
      -y|--yes)       ASSUME_YES=1 ;;
      --seed)         DO_SEED=1 ;;
      --start)        DO_START=1 ;;
      --dev)          RUN_DEV=1; DO_START=1 ;;
      --trust-local-auth) TRUST_LOCAL_AUTH=1 ;;
      --opencode)        OPEN_CODE=1 ;;
      --status)       MODE="status" ;;
      --stop)         MODE="stop" ;;
      --logs)         MODE="logs" ;;
      --clean)        MODE="clean" ;;
      --db-name=*)     DB_NAME="${1#*=}" ;;
      --db-user=*)     DB_USER="${1#*=}" ;;
      --db-password=*) DB_PASSWORD="${1#*=}" ;;
      --db-host=*)     DB_HOST="${1#*=}" ;;
      --db-port=*)     DB_PORT="${1#*=}" ;;
      --port=*)        API_PORT="${1#*=}" ;;
      --frontend-port=*) FRONTEND_PORT="${1#*=}" ;;
      --db-name|--db-user|--db-password|--db-host|--db-port|--port|--frontend-port)
        die "Missing value for $1" ;;
      *)              die "Unknown option: $1  (try --help)" ;;
    esac
    shift
  done

  [ -n "$DB_NAME" ] || DB_NAME="jasasane_app"

  # Reject non-numeric ports early rather than failing deep in the run.
  case "$API_PORT"     in ''|*[!0-9]*) die "--port must be a number" ;; esac
  case "$FRONTEND_PORT" in ''|*[!0-9]*) die "--frontend-port must be a number" ;; esac
  case "$DB_PORT"      in ''|*[!0-9]*) die "--db-port must be a number" ;; esac
}

# -----------------------------------------------------------------------------
# Platform detection / install hints
# -----------------------------------------------------------------------------
platform_kind() {
  case "$(uname -s)" in
    Darwin)                echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*)  echo "windows-bash" ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then echo "debian"
      elif command -v dnf >/dev/null 2>&1;    then echo "fedora"
      elif command -v yum >/dev/null 2>&1;    then echo "fedora"
      else echo "linux"
      fi ;;
    *) echo "unknown" ;;
  esac
}

node_install_hint() {
  case "$(platform_kind)" in
    debian)        echo "sudo apt-get update && sudo apt-get install -y nodejs npm" ;;
    fedora)        echo "sudo dnf install -y nodejs" ;;
    macos)         echo "brew install node" ;;
    # --accept-*: without these winget can stop on an interactive agreement
    # prompt, which reads as a hang. Matches setup.ps1's Get-InstallSpec.
    windows-bash)  echo "winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements" ;;
    *)             echo "https://nodejs.org/en/download  (install the LTS build)" ;;
  esac
}

pg_install_hint() {
  case "$(platform_kind)" in
    debian)        echo "sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib" ;;
    fedora)        echo "sudo dnf install -y postgresql-server postgresql-contrib" ;;
    macos)         echo "brew install postgresql@16 && brew services start postgresql@16" ;;
    windows-bash)  echo "winget install -e --id PostgreSQL.PostgreSQL.16 --accept-package-agreements --accept-source-agreements" ;;
    *)             echo "https://www.postgresql.org/download/" ;;
  esac
}

pg_start_hint() {
  case "$(platform_kind)" in
    debian)        echo "sudo systemctl enable --now postgresql" ;;
    fedora)        echo "sudo systemctl enable --now postgresql" ;;
    macos)         echo "brew services start postgresql@16" ;;
    windows-bash)  echo "net start postgresql-x64-16    # from an Administrator prompt" ;;
    *)             echo "start your PostgreSQL service" ;;
  esac
}

offer_install() {
  # offer_install <label> <hint> [post-start-hint]
  local label="$1" hint="$2" after="${3:-}"
  warn "$label is required."

  # The catch-all hints are web pages, not commands. eval on a URL throws and
  # reports "Install command failed: https://..." - honest but useless. Say what
  # actually has to happen instead. Mirrors the Manual branch in setup.ps1.
  case "$hint" in
    http://*|https://*)
      info  "No supported package manager found, so this cannot be installed automatically."
      # The URL carries a trailing "  (install the LTS build)" hint; keep the
      # link alone so it is copy-pasteable.
      info  "Download and install it from: ${hint%%  (*}"
      return 1
      ;;
  esac

  info  "Install command: $hint"
  if confirm "Install it now?" "n"; then
    info "Running: $hint"
    if eval "$hint"; then
      ok "$label installed."
      return 0
    else
      err "Install command failed: $hint"
      return 1
    fi
  fi
  return 1
}

node_major_version() {
  # -> the installed major version, or a negative sentinel: -1 = node is not on
  #    PATH, -2 = node is there but `node -p` said something unparseable. Both
  #    are negative so `-ge $MIN_NODE_MAJOR` stays false for them.
  # Only the first output line is considered, and it must be pure digits once
  # whitespace is stripped. A wrapper that prints a banner must not be able to
  # smuggle digits through - "using node 18.20" has to fail, not become 18200.
  local m
  command -v node >/dev/null 2>&1 || { printf '%s' "-1"; return 0; }
  m="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null | head -n 1)"
  m="$(printf '%s' "$m" | tr -d '[:space:]')"
  case "$m" in
    ''|*[!0-9]*) printf '%s' "-2" ;;
    *)           printf '%s' "$m" ;;
  esac
}

node_candidate_dirs() {
  # Well-known Node install directories, in probe order, one per line. Every
  # entry is checked for an actual `node` binary before it is printed, so a
  # stale or partial directory cannot put a broken path onto PATH. Bash analogue
  # of Get-NodeCandidateDirs in setup.ps1.
  #
  # The version-manager globs are expanded here rather than left to the caller
  # because those are the directories most likely to hold a working Node that
  # PATH does not show - a fresh `nvm install` writes a new version dir and
  # relies on `nvm use` to export it, which only affects the shell that ran it.
  local base dir
  for base in \
      "${NVM_DIR:-}/versions/node" \
      "$HOME/.nvm/versions/node" \
      "$HOME/.fnm/node-versions"; do
    # Skip empty expansions so the glob below cannot match the literal prefix.
    [ -n "${base#/}" ] || continue
    [ -d "$base" ] || continue
    # Highest version first, so a machine with several installed does not bind
    # the oldest one that happens to sort first.
    for dir in $(ls -1d "$base"/*/bin 2>/dev/null | sort -Vr); do
      [ -x "$dir/node" ] && printf '%s\n' "$dir"
    done
  done

  # Fixed locations. LOCALAPPDATA and ProgramFiles only exist on Git Bash, and
  # the MSYS root is /c there, so these are harmless no-ops elsewhere.
  for dir in \
      /usr/local/bin \
      /opt/homebrew/bin \
      /usr/local/opt/node/bin \
      "${LOCALAPPDATA:-/nonexistent}/Programs/nodejs" \
      "/c/Program Files/nodejs" \
      "/c/Program Files (x86)/nodejs"; do
    [ -x "$dir/node" ] && printf '%s\n' "$dir"
  done
}

resolve_node_on_path() {
  # -> 0 when `node` is callable in THIS process afterwards.
  #
  # A fresh install appends its directory to the environment of the shell that
  # will be started next, not to the already-running one, so this process cannot
  # see it by re-reading PATH alone. Probing the well-known locations is what
  # makes a working Node visible instead of telling the user to start a new
  # shell and re-run the whole setup. Port of Resolve-NodeOnPath in setup.ps1.
  local dir
  hash -r 2>/dev/null
  command -v node >/dev/null 2>&1 && return 0

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    # Prepend so a candidate actually wins over a stale earlier entry.
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
    hash -r 2>/dev/null
    if command -v node >/dev/null 2>&1; then
      info "Found Node.js in $dir (added to this session's PATH)."
      return 0
    fi
  done < <(node_candidate_dirs)

  return 1
}

node_problem() {
  # node_problem <major> -> why Node is unusable right now, or empty when usable.
  # Shared by the pre-install warning and the post-install re-check so the two
  # cannot drift apart.
  local major="$1" ver
  [ "$major" -ge "$MIN_NODE_MAJOR" ] && return 0
  case "$major" in
    -1) printf '%s' "Node.js is not on PATH." ;;
    -2) printf '%s' "Node.js is on PATH but 'node -p' did not report a version (a wrapper script or IDE shim may be shadowing it)." ;;
    *)  ver="$(node -v 2>/dev/null || echo 'unknown')"
        printf '%s' "Node.js $ver is too old (need >= $MIN_NODE_MAJOR)." ;;
  esac
}

ensure_node() {
  # Establishes whether Node/npm are usable, and NEVER aborts setup.
  #
  # This used to end in `die`, which meant a machine where Node is installed but
  # invisible to the running shell stopped the whole run before the .env, the
  # database and the dependencies. Node is a prerequisite for SOME steps, not for
  # all of them, so a missing toolchain downgrades those steps to "skipped, here's
  # why" (recorded in SKIPPED_STEP) and the rest of setup carries on. Port of
  # Ensure-Node in setup.ps1.
  local major ver
  major="$(node_major_version)"
  ver="$(node -v 2>/dev/null || echo 'unknown')"

  if [ "$major" -ge "$MIN_NODE_MAJOR" ]; then
    # No upper bound is enforced or warned about. The old ">20" warning was
    # actively misleading: it told users on Node 22/24 (which work fine) to
    # downgrade to Node 18, which has been end-of-life since April 2025.
    ok "Node.js $ver  (need >= $MIN_NODE_MAJOR)"
    return 0
  fi

  # Missing and too-old are the same problem to the user: the toolchain is not
  # usable yet. Both offer the install; only the wording differs.
  warn "$(node_problem "$major")"

  # Best effort: offer the install, but never let the installer's own exit code
  # decide the outcome. Only the re-verification below is authoritative. This
  # matters because a package manager can report a non-zero code for a package
  # that is in fact already present (winget answers 0x8A15002B for exactly that),
  # and aborting on it would stop setup in front of a working Node.
  offer_install "Node.js (>= $MIN_NODE_MAJOR)" "$(node_install_hint)" || true

  # Re-verify rather than assume. resolve_node_on_path also re-reads PATH and
  # probes the well-known install directories, so a Node that IS installed but
  # not yet on this shell's PATH is found here instead of being reported as
  # missing.
  if ! resolve_node_on_path; then
    NODE_READY=0
    err "Node.js is still not usable after attempting to install it."
    # Spelled out as a command substitution rather than a pipeline into a while
    # loop: the loop would run in a subshell, which is fine for printing but
    # obscures that nothing here is allowed to affect the caller's state.
    local searched
    searched="$(node_candidate_dirs)"
    if [ -n "$searched" ]; then
      info "Searched PATH and these directories:"
      while IFS= read -r dir; do
        [ -n "$dir" ] && info "  $dir"
      done <<EOF
$searched
EOF
    else
      info "No known Node install directory was found on this machine."
    fi
    info "Install it with: $(node_install_hint)"
    info "Continuing. The steps that need npm will be skipped - re-run setup"
    info "after Node is installed to complete them."
    return 0
  fi

  major="$(node_major_version)"
  ver="$(node -v 2>/dev/null || echo 'unknown')"

  if [ "$major" -ge "$MIN_NODE_MAJOR" ]; then
    ok "Node.js $ver  (need >= $MIN_NODE_MAJOR)"
    return 0
  fi

  # Usable, but too old for this project. Proceeding is the user's call, not
  # ours - warn clearly and let setup continue. Port of the equivalent branch in
  # Ensure-Node (setup.ps1:691).
  NODE_READY=1
  warn "Node.js $ver is below the required $MIN_NODE_MAJOR. Upgrade it:"
  info "  $(node_install_hint)"
  info "Continuing anyway - npm may fail on this version."
}

# -----------------------------------------------------------------------------
# Phase 1 - prerequisites
# -----------------------------------------------------------------------------
check_prereqs() {
  step "Checking prerequisites"

  # --- Node.js ---------------------------------------------------------------
  ensure_node

  # --- npm -------------------------------------------------------------------
  # npm ships in the same directory as node, so resolving Node above normally
  # makes it resolvable too. This stays a warning: without it, every later `npm`
  # call dies with a bare "command not found" instead of the message below, and
  # `die` here would throw away the .env and the database work.
  if [ "$NODE_READY" = "1" ] && command -v npm >/dev/null 2>&1; then
    ok "npm v$(npm -v)"
  else
    NPM_READY=0
    warn "npm is not available. It ships with Node.js."
    info "Once Node is installed: $(node_install_hint)"
    add_skipped_step "npm-dependent steps" "npm was not found"
  fi

  # --- PostgreSQL ------------------------------------------------------------
  if ! command -v psql >/dev/null 2>&1 && ! command -v pg_isready >/dev/null 2>&1; then
    offer_install "PostgreSQL (>= $MIN_PG_MAJOR)" "$(pg_install_hint)" \
      || die "PostgreSQL is required and was not installed."
  fi

  if command -v psql >/dev/null 2>&1; then
    local pg_raw pg_major
    pg_raw="$(psql --version 2>/dev/null)"
    # Matches "psql (PostgreSQL) 18.6 ..." - the first number inside the first
    # parenthesis, not a greedy match of the trailing distro/build suffix.
    pg_major="$(printf '%s' "$pg_raw" | sed -n 's/^[^)]*)[ ]*\([0-9][0-9]*\)\..*/\1/p')"
    if [ -z "$pg_major" ]; then
      warn "Could not parse the PostgreSQL version from '$pg_raw'. Continuing."
    elif [ "$pg_major" -lt "$MIN_PG_MAJOR" ]; then
      # Still fatal, unlike Node. The database phases immediately afterwards
      # speak to this exact client, so an old one fails with protocol errors
      # rather than a clean skip. Matches setup.ps1:743.
      die "PostgreSQL '$pg_raw' is older than the required $MIN_PG_MAJOR. Install a newer server."
    else
      ok "PostgreSQL client $pg_raw  (need >= $MIN_PG_MAJOR)"
    fi
  else
    ok "psql not on PATH (will use the 'postgres' system account if present)"
  fi

  wait_for_postgres
}

wait_for_postgres() {
  local attempt=0
  if command -v pg_isready >/dev/null 2>&1; then
    info "Waiting for PostgreSQL on $DB_HOST:$DB_PORT ..."
    while [ $attempt -lt 30 ]; do
      if pg_isready -h "$DB_HOST" -p "$DB_PORT" -q >/dev/null 2>&1; then
        ok "PostgreSQL is accepting connections on $DB_HOST:$DB_PORT"
        return 0
      fi
      attempt=$((attempt + 1))
      sleep 1
    done
    warn "PostgreSQL is not answering on $DB_HOST:$DB_PORT after 30s."
    info "Start it with: $(pg_start_hint)"
    confirm "Retry the check now?" "y" || die "Cannot continue without a running PostgreSQL."
    return 0
  fi
  # No pg_isready (e.g. macOS Homebrew layout): fall back to a TCP probe.
  info "Probing $DB_HOST:$DB_PORT ..."
  if port_in_use "$DB_PORT"; then
    ok "Something is listening on $DB_HOST:$DB_PORT"
    return 0
  fi
  warn "Nothing is listening on $DB_HOST:$DB_PORT and pg_isready is unavailable."
  info "Start PostgreSQL with: $(pg_start_hint)"
  confirm "Continue anyway?" "y" || die "Cannot continue without a running PostgreSQL."
}

# -----------------------------------------------------------------------------
# Phase 2 - backend/.env
# -----------------------------------------------------------------------------
env_get() {
  # env_get <file> <key>
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | head -n 1
}

read_env_value() {
  # read_env_value <key> <current> -> echoes current or the value from .env
  local key="$1" current="$2" value
  if [ -n "$current" ]; then printf '%s' "$current"; return 0; fi
  value="$(env_get "$BACKEND_DIR/.env" "$key")"
  value="${value%$'\r'}"
  if [ "$value" = "your_db_user" ] || [ "$value" = "your_db_password" ]; then
    value=""
  fi
  printf '%s' "$value"
}

write_env() {
  local file="$1"
  cat > "$file" <<ENVEOF
PORT=${API_PORT}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
JWT_SECRET=${JWT_SECRET}
OTP_EXPIRY_MINUTES=5
MAX_LOGIN_ATTEMPTS=3
LOCKOUT_MINUTES=15
ENVEOF
  chmod 600 "$file" 2>/dev/null || true
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 48
  else
    node -e 'console.log(require("crypto").randomBytes(48).toString("hex"))'
  fi
}

ensure_env() {
  step "Configuring the backend environment"

  local existing=""
  if [ -f "$BACKEND_DIR/.env" ]; then
    existing="yes"
    ok "backend/.env already exists - reusing it (it is never overwritten)"
  else
    [ -f "$BACKEND_DIR/.env.example" ] || die "backend/.env.example is missing; cannot create backend/.env"
    info "Creating backend/.env from backend/.env.example"
  fi

  DB_NAME="$(read_env_value DB_NAME "$DB_NAME")"
  DB_USER="$(read_env_value DB_USER "$DB_USER")"
  DB_PASSWORD="$(read_env_value DB_PASSWORD "$DB_PASSWORD")"
  DB_HOST="$(read_env_value DB_HOST "$DB_HOST")"
  DB_PORT="$(read_env_value DB_PORT "$DB_PORT")"
  JWT_SECRET="$(read_env_value JWT_SECRET "$JWT_SECRET")"

  # PORT inside .env is only consulted for a *new* file; an existing one wins.
  if [ -n "$existing" ]; then
    local env_port
    env_port="$(env_get "$BACKEND_DIR/.env" PORT)"
    env_port="${env_port%$'\r'}"
    if [ -n "$env_port" ] && [ "$env_port" != "$API_PORT" ]; then
      API_PORT="$env_port"
      info "Using PORT=$API_PORT from the existing backend/.env"
    fi
  fi

  [ -n "$DB_NAME" ] || DB_NAME="jasasane_app"

  if [ -z "$DB_USER" ]; then
    prompt DB_USER "PostgreSQL user" "postgres"
  fi
  if [ "$TRUST_LOCAL_AUTH" = "1" ]; then
    DB_PASSWORD=""
    info "--trust-local-auth: not asking for a password (PostgreSQL trusts local connections)"
  elif [ -z "$DB_PASSWORD" ]; then
    prompt_secret DB_PASSWORD "PostgreSQL password for '$DB_USER'"
    if [ -z "$DB_PASSWORD" ]; then
      die "An empty password was supplied. Check the password for '$DB_USER' and try again."
    fi
  fi
  if [ -z "$JWT_SECRET" ]; then
    JWT_SECRET="$(generate_secret)"
    info "Generated a fresh 48-byte JWT_SECRET"
  fi

  if [ -n "$existing" ]; then
    info "Resolved configuration:"
    info "  DB      $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    info "  Backend  http://localhost:$API_PORT"
    return 0
  fi

  write_env "$BACKEND_DIR/.env"
  ok "Wrote backend/.env (mode 600, gitignored)"
  info "  DB      $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
  info "  Backend  http://localhost:$API_PORT"
}

# -----------------------------------------------------------------------------
# Phase 3 - database
# -----------------------------------------------------------------------------
psql_run() {
  # psql_run <database> <sql>
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$1" \
    -v ON_ERROR_STOP=1 -tAc "$2" 2>/dev/null
}

psql_admin() {
  # psql_admin <sql> - always against the maintenance database
  psql_run postgres "$1"
}

ensure_database() {
  step "Preparing the database"

  local connected=""
  local reason=""
  if [ "$TRUST_LOCAL_AUTH" = "1" ]; then
    connected="yes"
    reason="--trust-local-auth (no password check)"
  elif [ "$(id -un 2>/dev/null)" = "postgres" ] || [ -z "$DB_USER" ]; then
    connected="yes"
    reason="running as the 'postgres' system account"
  fi

  # 1. Verify the credentials. A read-only query, nothing is mutated yet.
  if [ -z "$connected" ]; then
    if psql_run postgres "SELECT 1;" >/dev/null 2>&1; then
      ok "Authenticated as '$DB_USER'"
    else
      err "PostgreSQL rejected the credentials for '$DB_USER'."
      info "Check the password, and that the host is right ($DB_HOST:$DB_PORT)."
      info "If pg_hba.conf asks for a password over TCP, set one with:"
      info "  sudo -u postgres psql -c \"ALTER USER $DB_USER WITH PASSWORD '...';\""
      info "If pg_hba.conf is set to 'trust' instead, re-run with --trust-local-auth."
      if have_tty && confirm "Re-enter the database password?" "y"; then
        prompt_secret DB_PASSWORD "PostgreSQL password for '$DB_USER'"
        write_env "$BACKEND_DIR/.env"
        if psql_run postgres "SELECT 1;" >/dev/null 2>&1; then
          ok "Authenticated as '$DB_USER'"
          connected="yes"
        else
          die "Still failing to authenticate as '$DB_USER'."
        fi
      else
        die "Cannot continue without valid database credentials."
      fi
    fi
  else
    ok "Not verifying the password: $reason"
  fi

  # 2. Create the database if it is missing.
  local exists
  exists="$(psql_admin "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';")"
  if [ "$exists" = "1" ]; then
    ok "Database '$DB_NAME' already exists"
  else
    info "Creating database '$DB_NAME'"
    if psql_admin "CREATE DATABASE \"$DB_NAME\";" >/dev/null; then
      ok "Created database '$DB_NAME'"
    else
      err "CREATE DATABASE '$DB_NAME' failed."
      info "If the name is not a valid identifier, pass a simpler one: --db-name=myapp"
      info "If the credentials are wrong, re-run with --db-password=... (or --trust-local-auth"
      info "if pg_hba.conf trusts local connections)."
      die "Could not create the database."
    fi
  fi

  # 3. Confirm we can actually open it (catches missing privileges early).
  if psql_run "$DB_NAME" "SELECT 1;" >/dev/null 2>&1; then
    ok "Database '$DB_NAME' is reachable"
  else
    err "'$DB_USER' cannot open database '$DB_NAME'."
    info "Grant access with: sudo -u postgres psql -c \"GRANT ALL ON DATABASE \\\"$DB_NAME\\\" TO \\\"$DB_USER\\\";\""
    die "Database access denied."
  fi

  info "Setup creates the database only. The tables (users, otps, records) are"
  info "created by the backend the first time you run it (npm run dev / npm start)."
}

# -----------------------------------------------------------------------------
# Phase 4 - dependencies
# -----------------------------------------------------------------------------
install_deps() {
  # install_deps <dir> <label> <sentinel-package>
  # -> 0 when the dependencies are in place afterwards, 1 when they are not.
  local dir="$1" label="$2" sentinel="$3"

  if [ "$NPM_READY" != "1" ]; then
    warn "Skipping the $label dependencies - npm is not available."
    add_skipped_step "$label dependencies (npm ci)" "npm was not found"
    return 1
  fi

  if [ -f "$dir/node_modules/$sentinel/package.json" ]; then
    ok "$label dependencies already installed (found $sentinel)"
    return 0
  fi

  info "Installing $label dependencies (this can take a few minutes)..."
  if [ -f "$dir/package-lock.json" ]; then
    ( cd "$dir" && npm ci --no-audit --no-fund ) && { ok "$label dependencies installed (npm ci)"; return 0; }
    warn "'npm ci' failed. Retrying with 'npm install' ..."
  fi
  if ( cd "$dir" && npm install --no-audit --no-fund ); then
    ok "$label dependencies installed (npm install)"
    return 0
  fi

  err "Installing $label dependencies failed."
  if [ "$label" = "backend" ]; then
    info "The backend uses bcrypt, a native module. If it could not download a prebuilt"
    info "binary for your platform you will need build tools:"
    info "  Ubuntu  sudo apt-get install -y build-essential python3"
    info "  macOS   xcode-select --install"
    info "  Windows npm install --global windows-build-tools"
  fi
  # Recorded, not fatal: the database and .env are already prepared, so a user
  # who can fix npm (or a proxy) should not have to redo that work. Matches the
  # Add-SkippedStep call in Install-Deps (setup.ps1:1168).
  add_skipped_step "$label dependencies" "npm install failed"
  return 1
}

install_dependencies() {
  step "Installing dependencies"
  # Both are attempted even when the first fails, so one broken lockfile does
  # not hide the state of the other.
  install_deps "$BACKEND_DIR"  "backend"  "express"  || true
  install_deps "$FRONTEND_DIR" "frontend" "react-scripts" || true
}

# -----------------------------------------------------------------------------
# Phase 4b - OpenCode CLI (opt-in)
# -----------------------------------------------------------------------------
opencode_install_hint() {
  echo "npm install --global opencode-ai@latest"
}

resolve_opencode_on_path() {
  # -> 0 when `opencode` is callable in this shell afterwards.
  # Never prompts, so --status stays non-interactive.
  command -v opencode >/dev/null 2>&1 && return 0

  # A global npm install can land in a bin directory that is not on PATH. On unix
  # that is normally already covered, but the probe makes the check independent of
  # the user's shell profile. Port of Resolve-OpenCodeOnPath (setup.ps1).
  local prefix bin
  prefix="$(npm prefix -g 2>/dev/null)" || prefix=""
  for bin in "$prefix/bin" "$prefix"; do
    [ -n "$bin" ] || continue
    [ -x "$bin/opencode" ] || continue
    PATH="$bin:$PATH"
    export PATH
    hash -r 2>/dev/null || true
    info "Found opencode in $bin (added to this session's PATH)."
    return 0
  done
  return 1
}

opencode_version() {
  command -v opencode >/dev/null 2>&1 || { echo "unknown"; return 0; }
  # First line only, and stderr discarded: a wrapper that prints a banner would
  # otherwise leak into the version line.
  local v
  v="$(opencode --version 2>/dev/null | head -n 1)"
  [ -n "$v" ] && echo "$v" || echo "unknown"
}

write_opencode_config() {
  # Creates opencode.json when it is missing. Never overwrites one that exists: a
  # developer's model and permission choices are theirs.
  local file="$ROOT/opencode.json"
  if [ -f "$file" ]; then
    info "opencode.json already exists - leaving it as it is."
    return 0
  fi

  # Quoted heredoc delimiter, deliberately: the content contains "$schema" and a
  # literal "*" key, both of which an unquoted heredoc would try to expand.
  if cat > "$file" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle",
  "default_agent": "build",
  "permission": {
    "*": "ask",
    "read": "allow",
    "view": "allow",
    "grep": "allow",
    "glob": "allow",
    "edit": "ask",
    "bash": "ask",
    "task": "ask",
    "skill": "ask",
    "todowrite": "allow",
    "webfetch": "allow",
    "websearch": "allow",
    "question": "allow",
    "external_directory": "ask"
  }
}
JSON
  then
    ok "Wrote opencode.json (model opencode/big-pickle, default agent build)."
    info "It is listed in .gitignore, so it stays a local file - it will not be committed."
  else
    err "Could not write opencode.json."
  fi
}

ensure_opencode() {
  step "Checking the OpenCode CLI"

  if [ "$NPM_READY" != "1" ]; then
    warn "Skipping the OpenCode CLI - npm is not available."
    add_skipped_step "the OpenCode CLI" "npm was not found"
    return 0
  fi

  if resolve_opencode_on_path; then
    # Already installed: report and stop. Asking "Install it now?" here would be
    # the exact complaint this feature exists to remove.
    ok "opencode $(opencode_version)"
  else
    info "Install command: $(opencode_install_hint)"
    if confirm "Install it now?" "n"; then
      info "Running it now; a global npm install can take a minute."
      if npm install --global opencode-ai@latest; then
        # Verification, not the exit code, is authoritative - same rule as
        # ensure_node. The bin directory may not be on PATH yet.
        resolve_opencode_on_path >/dev/null 2>&1 || true
        if command -v opencode >/dev/null 2>&1; then
          ok "opencode $(opencode_version) installed."
        else
          err "npm reported success but \`opencode\` is still not callable."
          info "It was installed into the npm global prefix, which is not on PATH."
          info "Add that directory to PATH and open a new terminal, then re-run."
          add_skipped_step "the OpenCode CLI" "installed but not on PATH"
        fi
      else
        err "npm install --global opencode-ai@latest failed."
        info "A global install may need elevated permissions on your npm prefix:"
        info "  npm prefix -g"
        add_skipped_step "the OpenCode CLI" "npm install failed"
      fi
    else
      # Declining the install must not skip the config: --opencode was an explicit
      # request for the OpenCode workspace, and writing a gitignored local file is
      # not the system change the confirmation above was guarding against.
      info "Skipped the install. Run it later with: $(opencode_install_hint)"
    fi
  fi

  write_opencode_config
}

# -----------------------------------------------------------------------------
# Phase 5 - seed (opt-in, destructive)
# -----------------------------------------------------------------------------
run_seed() {
  step "Seeding demo data"

  if [ "$NPM_READY" != "1" ]; then
    warn "Skipping the seed - npm is not available."
    add_skipped_step "seed data" "npm was not found"
    return 1
  fi
  # The seed requires bcrypt, which lives in the backend's node_modules, so it
  # cannot run before install_deps succeeded. Port of Invoke-Seed (setup.ps1:1192).
  if [ ! -f "$BACKEND_DIR/node_modules/express/package.json" ]; then
    warn "Skipping the seed - the backend dependencies are not installed yet."
    add_skipped_step "seed data" "backend dependencies missing"
    return 1
  fi

  warn "The seed script is DESTRUCTIVE. It will:"
  info "  * DELETE every row from the 'records' table"
  info "  * DELETE every row from the 'otps' table"
  info "  * DELETE every user except 09999999999, 09111111111, 09222222222"
  info "It then re-creates 3 users (password: Password@123) and 10 member records."

  if ! confirm_typed "Proceed with seeding?" "SEED"; then
    info "Seed cancelled. Existing data left untouched."
    return 0
  fi

  if ( cd "$BACKEND_DIR" && npm run seed ); then
    ok "Seed complete."
    return 0
  fi

  err "Seeding failed."
  add_skipped_step "seed data" "npm run seed exited non-zero"
  return 1
}

# -----------------------------------------------------------------------------
# Port helpers
# -----------------------------------------------------------------------------
port_in_use() {
  # Returns 0 when the port IS in use, 1 when it is free.
  # Uses Node (a hard prerequisite) so this works identically everywhere.
  # Binds 0.0.0.0 so a process listening on any interface is detected.
  node -e '
    const net = require("net");
    const port = Number(process.argv[1]);
    const srv = net.createServer();
    srv.once("error", () => process.exit(0));
    srv.once("listening", () => srv.close(() => process.exit(1)));
    srv.listen(port, "0.0.0.0");
  ' "$1" >/dev/null 2>&1
}

pids_on_port() {
  local port="$1" pids=''
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -ti "tcp:${port}" -sTCP:LISTEN 2>/dev/null)"
  fi
  if [ -z "$pids" ] && command -v ss >/dev/null 2>&1; then
    pids="$(ss -ltnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | grep -oE 'pid=[0-9]+' | cut -d= -f2)"
  fi
  if [ -z "$pids" ] && command -v netstat >/dev/null 2>&1; then
    pids="$(netstat -ano 2>/dev/null | grep -E "[:.]${port}[[:space:]].*LISTENING" | awk '{print $NF}')"
  fi
  printf '%s' "$pids"
}

describe_pids() {
  local pids="$1" pid
  [ -n "$pids" ] || return 0
  for pid in $pids; do
    info "  pid $pid: $(ps -o comm= -p "$pid" 2>/dev/null || echo 'unknown process')"
  done
}

assert_ports_free() {
  # port_in_use shells out to node, so without a working Node it cannot tell a
  # free port from an occupied one - every probe would fail and report "free".
  # That is worse than not checking: the script would then try to start servers
  # onto ports someone else owns.
  if [ "$NODE_READY" != "1" ]; then
    warn "Skipping the port check - it needs Node.js, which is not available."
    return 0
  fi

  step "Checking ports"
  local busy=0
  if port_in_use "$API_PORT"; then
    err "Port $API_PORT is already in use (needed by the backend)."
    describe_pids "$(pids_on_port "$API_PORT")"
    busy=1
  else
    ok "Port $API_PORT is free"
  fi
  if port_in_use "$FRONTEND_PORT"; then
    err "Port $FRONTEND_PORT is already in use (needed by the frontend)."
    info "This one matters: the React dev server asks interactively whether to"
    info "use a different port, which would hang a background start forever."
    describe_pids "$(pids_on_port "$FRONTEND_PORT")"
    busy=1
  else
    ok "Port $FRONTEND_PORT is free"
  fi
  [ "$busy" = "0" ] || die "Free the ports above (or pass --port / --frontend-port) and re-run."

  if [ "$API_PORT" != "5000" ]; then
    warn "--port=$API_PORT differs from the default 5000."
    note "frontend/src/services/api.js hardcodes http://localhost:5000 - edit it or the UI will not reach the API."
  fi
  if [ "$FRONTEND_PORT" != "3000" ]; then
    info "Frontend will listen on http://localhost:$FRONTEND_PORT"
  fi
}

# -----------------------------------------------------------------------------
# Phase 6 - start / stop
# -----------------------------------------------------------------------------
pid_alive() {
  local pid="${1:-}"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

read_pid() {
  local file="$1" pid=''
  [ -f "$file" ] && pid="$(tr -dc '0-9' < "$file" 2>/dev/null)"
  printf '%s' "$pid"
}

kill_tree() {
  local pid="$1" sig="$2"
  kill "-$sig" "$pid" >/dev/null 2>&1
}

# npm spawns node as a child, so killing the recorded PID alone leaves the real
# server running and still holding the port. Walk the tree depth-first and
# signal children before their parent.
child_pids() {
  ps -eo pid=,ppid= 2>/dev/null | awk -v p="$1" '$2==p {print $1}'
}

# PIDs come from files on disk and from port lookups, so never trust them
# blindly: refuse init, this script, and anything that spawned this script.
ancestor_pids() {
  local pid="$$" ppid i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ppid="$(ps -eo pid=,ppid= 2>/dev/null | awk -v p="$pid" '$1==p {print $2; exit}')"
    [ -z "$ppid" ] && break
    printf '%s\n' "$ppid"
    pid="$ppid"
  done
}

SAFE_ANCESTORS=""

safe_to_kill() {
  local pid="$1"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$pid" -gt 1 ] 2>/dev/null || return 1
  [ "$pid" != "$$" ] || return 1
  if [ -z "$SAFE_ANCESTORS" ]; then
    SAFE_ANCESTORS=" $(ancestor_pids | tr '\n' ' ') "
  fi
  case "$SAFE_ANCESTORS" in
    *" $pid "*) return 1 ;;
  esac
  return 0
}

kill_tree_recursive() {
  local pid="$1" sig="$2" child
  for child in $(child_pids "$pid"); do
    safe_to_kill "$child" || continue
    kill_tree_recursive "$child" "$sig"
  done
  safe_to_kill "$pid" && kill_tree "$pid" "$sig"
}

descendant_pids() {
  local pid="$1" child
  for child in $(child_pids "$pid"); do
    safe_to_kill "$child" || continue
    descendant_pids "$child"
    printf '%s\n' "$child"
  done
}

stop_one() {
  # stop_one <label> <pidfile> <port>
  local label="$1" pidfile="$2" port="$3" stopped=0 pid pids
  pid="$(read_pid "$pidfile")"

  if pid_alive "$pid"; then
    kill_tree_recursive "$pid" TERM
    stopped=1
  fi

  # Backstop: also sweep whatever still owns the port, plus any descendants the
  # recorded PID no longer accounts for (e.g. the PID file is stale).
  pids="$(pids_on_port "$port")"
  for pid in $pids; do
    if safe_to_kill "$pid"; then
      kill_tree_recursive "$pid" TERM
      stopped=1
    fi
  done

  if [ "$stopped" = "0" ]; then
    info "$label: not running"
    rm -f "$pidfile"
    return 0
  fi

  # Give them a moment, then escalate.
  local i=0
  while [ $i -lt 10 ]; do
    if ! pid_alive "$(read_pid "$pidfile")" && [ -z "$(pids_on_port "$port")" ]; then
      break
    fi
    sleep 0.5
    i=$((i + 1))
  done
  pid="$(read_pid "$pidfile")"
  pid_alive "$pid" && kill_tree_recursive "$pid" KILL
  for pid in $(pids_on_port "$port") $(descendant_pids "$(read_pid "$pidfile")"); do
    kill_tree_recursive "$pid" KILL
  done

  rm -f "$pidfile"
  ok "$label stopped"
}

do_stop() {
  step "Stopping services"
  mkdir -p "$LOG_DIR"
  stop_one "Backend"  "$BACKEND_PID"  "$API_PORT"
  stop_one "Frontend" "$FRONTEND_PID" "$FRONTEND_PORT"
}

http_ok() {
  # http_ok <url>  -> 0 if the URL responds at all
  node -e '
    const url = process.argv[1];
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 4000);
    fetch(url, { signal: ctl.signal })
      .then(() => { clearTimeout(t); process.exit(0); })
      .catch(() => { clearTimeout(t); process.exit(1); });
  ' "$1" >/dev/null 2>&1
}

api_healthy() {
  node -e '
    const url = process.argv[1];
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 4000);
    fetch(url, { signal: ctl.signal })
      .then((r) => r.json())
      .then((j) => { clearTimeout(t); process.exit(j && j.status === "OK" ? 0 : 1); })
      .catch(() => { clearTimeout(t); process.exit(1); });
  ' "$1" >/dev/null 2>&1
}

tail_log_on_failure() {
  local file="$1" lines="${2:-30}"
  [ -f "$file" ] || return 0
  err "Last $lines lines of $(basename "$file"):"
  tail -n "$lines" "$file" | sed 's/^/      | /' >&2
}

start_one() {
  # start_one <label> <dir> <pidfile> <logfile> [env assignments...]
  local label="$1" dir="$2" pidfile="$3" logfile="$4"; shift 4
  local existing
  existing="$(read_pid "$pidfile")"
  if pid_alive "$existing"; then
    ok "$label is already running (pid $existing)"
    return 0
  fi
  rm -f "$pidfile"
  : > "$logfile"
  ( cd "$dir" && exec env "$@" ) >>"$logfile" 2>&1 &
  local pid=$!
  printf '%s' "$pid" > "$pidfile"
  info "$label starting (pid $pid) -> ${logfile#$ROOT/}"
}

do_start() {
  if [ "$NPM_READY" != "1" ]; then
    warn "Skipping the start: npm is not available, so the app cannot be launched."
    add_skipped_step "start the backend and frontend" "npm was not found"
    return 1
  fi

  step "Starting services"
  mkdir -p "$LOG_DIR"

  start_one "Backend"  "$BACKEND_DIR"  "$BACKEND_PID"  "$BACKEND_LOG" \
    "NODE_ENV=development" "npm" "start"
  start_one "Frontend" "$FRONTEND_DIR" "$FRONTEND_PID" "$FRONTEND_LOG" \
    "PORT=$FRONTEND_PORT" "BROWSER=none" "CI=false" "npm" "start"

  # Readiness: backend first, because the frontend is useless without it.
  info "Waiting for the backend on http://localhost:$API_PORT/api/health ..."
  local i=0
  while [ $i -lt 60 ]; do
    if api_healthy "http://localhost:$API_PORT/api/health"; then
      ok "Backend is healthy"
      break
    fi
    if ! pid_alive "$(read_pid "$BACKEND_PID")"; then
      err "The backend process exited."
      tail_log_on_failure "$BACKEND_LOG"
      err "Common causes: DB_NAME/DB_USER/DB_PASSWORD wrong in backend/.env,"
      err "PostgreSQL not running, or port $API_PORT taken."
      do_stop >/dev/null 2>&1
      die "Backend failed to start."
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ $i -ge 60 ]; then
    err "Backend did not become healthy within 60s."
    tail_log_on_failure "$BACKEND_LOG"
    do_stop >/dev/null 2>&1
    die "Backend failed the health check."
  fi

  info "Waiting for the frontend on http://localhost:$FRONTEND_PORT ..."
  i=0
  while [ $i -lt 90 ]; do
    if http_ok "http://localhost:$FRONTEND_PORT"; then
      ok "Frontend is serving"
      break
    fi
    if ! pid_alive "$(read_pid "$FRONTEND_PID")"; then
      err "The frontend process exited."
      tail_log_on_failure "$FRONTEND_LOG"
      do_stop >/dev/null 2>&1
      die "Frontend failed to start."
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ $i -ge 90 ]; then
    err "Frontend did not answer within 90s (the first CRA compile is slow)."
    tail_log_on_failure "$FRONTEND_LOG"
    do_stop >/dev/null 2>&1
    die "Frontend failed to start."
  fi
}

do_start_foreground_backend() {
  if [ "$NPM_READY" != "1" ]; then
    warn "Cannot start the backend: npm is not available."
    add_skipped_step "run the backend in the foreground" "npm was not found"
    return 1
  fi

  step "Starting the backend with nodemon (foreground)"
  info "Press Ctrl+C to stop."
  ( cd "$BACKEND_DIR" && exec npm run dev )
}

# -----------------------------------------------------------------------------
# Status / logs / clean
# -----------------------------------------------------------------------------
do_status() {
  step "Status"

  local pid
  pid="$(read_pid "$BACKEND_PID")"
  if pid_alive "$pid"; then
    ok "Backend  running  pid $pid  http://localhost:$API_PORT"
  else
    info "Backend  stopped"
  fi

  pid="$(read_pid "$FRONTEND_PID")"
  if pid_alive "$pid"; then
    ok "Frontend running  pid $pid  http://localhost:$FRONTEND_PORT"
  else
    info "Frontend stopped"
  fi

  if [ -f "$BACKEND_DIR/.env" ]; then
    ok "backend/.env present"
  else
    info "backend/.env missing"
  fi
  if command -v pg_isready >/dev/null 2>&1; then
    if pg_isready -h "$DB_HOST" -p "$DB_PORT" -q >/dev/null 2>&1; then
      ok "PostgreSQL accepting connections on $DB_HOST:$DB_PORT"
    else
      info "PostgreSQL not answering on $DB_HOST:$DB_PORT"
    fi
  fi
  if [ -f "$BACKEND_DIR/node_modules/express/package.json" ]; then
    ok "Backend dependencies installed"
  else
    info "Backend dependencies not installed"
  fi
  if [ -f "$FRONTEND_DIR/node_modules/react-scripts/package.json" ]; then
    ok "Frontend dependencies installed"
  else
    info "Frontend dependencies not installed"
  fi

  # resolve_opencode_on_path / opencode_version never prompt, so reporting the
  # CLI here keeps --status non-interactive.
  if resolve_opencode_on_path; then
    ok "OpenCode CLI $(opencode_version)"
  else
    info "OpenCode CLI not installed (./setup.sh --opencode installs it)"
  fi
}

do_logs() {
  if [ ! -f "$BACKEND_LOG" ] && [ ! -f "$FRONTEND_LOG" ]; then
    die "No logs found in ${LOG_DIR#$ROOT/}. Start the app first."
  fi
  step "Tailing logs (Ctrl+C to stop)"
  info "The OTP is printed by the backend: grep -i otp ${BACKEND_LOG#$ROOT/} | tail -1"
  [ -f "$BACKEND_LOG" ]  && tail -n 20 -f "$BACKEND_LOG"  &
  local tail_pid=$!
  [ -f "$FRONTEND_LOG" ] && tail -n 20 -f "$FRONTEND_LOG" &
  local tail2_pid=$!
  trap 'kill $tail_pid $tail2_pid 2>/dev/null; exit 0' INT TERM
  wait
}

do_clean() {
  step "Cleaning"
  do_stop
  if confirm "Delete backend/node_modules and frontend/node_modules?" "n"; then
    rm -rf "$BACKEND_DIR/node_modules" "$FRONTEND_DIR/node_modules"
    ok "node_modules removed (the next setup run reinstalls them)"
  else
    info "Kept node_modules"
  fi
  if confirm "Delete $LOG_DIR and backend/.env?" "n"; then
    rm -rf "$LOG_DIR" "$BACKEND_DIR/.env"
    ok "Logs and backend/.env removed"
  else
    info "Kept logs and backend/.env"
  fi
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
  cat <<SUMMARY

$(printf '%s%s  Membership app is up%s' "$C_GREEN" "$C_BOLD" "$C_RESET")

    Frontend   http://localhost:${FRONTEND_PORT}
    Backend    http://localhost:${API_PORT}   (health: /api/health)
    Database   ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}
    Seeded     $([ "$DO_SEED" = "1" ] && echo yes || echo no)

$(printf '%s  Demo logins (after --seed)%s' "$C_BOLD" "$C_RESET")

    Admin      09999999999  /  Password@123
    Regular    09111111111  /  Password@123
    Regular    09222222222  /  Password@123

$(printf '%s  Where to look next%s' "$C_BOLD" "$C_RESET")

    Logs       ./setup.sh --logs
    OTP        grep -i otp ${BACKEND_LOG#$ROOT/} | tail -1
               (OTPs are simulated - printed to the backend console, not sent by SMS)
    Stop       ./setup.sh --stop
    Status     ./setup.sh --status

SUMMARY
}

print_skipped_report() {
  has_skipped_steps || return 0

  local i
  printf '\n%s%s  SETUP INCOMPLETE%s\n' "$C_YELLOW" "$C_BOLD" "$C_RESET"
  printf '%s  Some steps could not run:%s\n' "$C_YELLOW" "$C_RESET"
  for i in "${!SKIPPED_STEP[@]}"; do
    printf '%s    - %s  (%s)%s\n' \
      "$C_YELLOW" "${SKIPPED_STEP[$i]}" "${SKIPPED_REASON[$i]}" "$C_RESET"
  done
  printf '\n'
  printf '%s  Fix the cause above, then re-run setup - it resumes where it left%s\n' "$C_YELLOW" "$C_RESET"
  printf '%s  off and re-uses backend/.env as it is.%s\n\n' "$C_YELLOW" "$C_RESET"
}

print_setup_summary() {
  local seeded="no" deps="installed" banner opencode_state=""
  [ "$DO_SEED" = "1" ] && seeded="yes"
  [ "$NPM_READY" = "1" ] || deps="NOT installed"
  if [ "$OPEN_CODE" = "1" ]; then
    if command -v opencode >/dev/null 2>&1; then
      opencode_state="$(opencode_version)"
    else
      opencode_state="NOT installed"
    fi
  fi

  print_skipped_report

  # Built here rather than inline in the heredoc so that --opencode not being
  # passed leaves no stray blank line in the summary.
  local opencode_line=""
  [ "$OPEN_CODE" = "1" ] && opencode_line="$(printf '    OpenCode   %s' "$opencode_state")"

  # Green only when nothing was skipped, so the banner cannot claim success on
  # a run that left work undone.
  if has_skipped_steps; then
    banner="$C_YELLOW$C_BOLD  Setup finished with skipped steps - nothing was started$C_RESET"
  else
    banner="$C_GREEN$C_BOLD  Setup complete - nothing was started$C_RESET"
  fi

  cat <<SUMMARY

$banner

    Database   ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}
    Backend    .env written
    Frontend   dependencies ${deps}
    Seeded     ${seeded}
${opencode_line}
$(printf '%s  Run the app%s' "$C_BOLD" "$C_RESET")

    Backend    cd ${BACKEND_DIR#$ROOT/} && npm run dev
               -> http://localhost:${API_PORT}
    Frontend   cd ${FRONTEND_DIR#$ROOT/} && npm start
               -> http://localhost:${FRONTEND_PORT}  (in a second terminal)

    The tables (users, otps, records) are created by the backend on its
    first boot, so they appear the moment you run it.

$(printf '%s  Other actions%s' "$C_BOLD" "$C_RESET")

    Both at once   ./setup.sh --start
    Logs           ./setup.sh --logs
    Stop           ./setup.sh --stop
    Status         ./setup.sh --status

SUMMARY
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  parse_args "$@"

  case "$MODE" in
    status)  do_status; exit 0 ;;
    stop)    do_stop; exit 0 ;;
    logs)    do_logs; exit 0 ;;
    clean)   do_clean; exit 0 ;;
  esac

  [ -d "$BACKEND_DIR" ]  || die "backend/ not found next to setup.sh. Run it from inside the repository."
  [ -d "$FRONTEND_DIR" ] || die "frontend/ not found next to setup.sh. Run it from inside the repository."

  printf '%s%s  membership-app setup%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  info "Repository root: $ROOT"

  check_prereqs
  ensure_env
  ensure_database
  install_dependencies

  # Opt-in only, and last: it needs npm (known by now) and has nothing to do with
  # the app, so it must not sit inside the backend -> seed -> frontend chain.
  [ "$OPEN_CODE" = "1" ] && ensure_opencode

  if [ "$DO_SEED" = "1" ]; then
    run_seed
  fi

  # Setup is complete at this point. Starting the app is opt-in (--start / --dev).
  if [ "$DO_START" = "0" ]; then
    print_setup_summary
    exit 0
  fi

  assert_ports_free

  if [ "$RUN_DEV" = "1" ]; then
    do_start_foreground_backend || print_skipped_report
    exit 0
  fi

  # do_start returning non-zero means it never ran (npm missing), not that the
  # servers came up and then died - a real start failure still dies inside it.
  # Printing the "app is up" banner in that case would be a lie, so report the
  # skips instead. Exit code stays 0 so a re-run is the obvious next step.
  if do_start; then
    print_summary
  else
    print_skipped_report
    printf '\n%s%s  Nothing was started%s\n' "$C_YELLOW" "$C_BOLD" "$C_RESET"
  fi
}

main "$@"
