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
MODE="setup"

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
  # Missing and too-old are the same problem to the user: the toolchain is not
  # usable yet. Both offer the install; only the wording differs.
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

  warn "$(node_problem "$major")"

  offer_install "Node.js (>= $MIN_NODE_MAJOR)" "$(node_install_hint)" \
    || die "Node.js >= $MIN_NODE_MAJOR is required. Fix: $(node_install_hint)"

  # Re-verify rather than assume. A fresh install adds a PATH entry, but a Node
  # that was already installed by other means can sit earlier on PATH and keep
  # winning - in which case the user still sees the old version and needs to be
  # told exactly why, instead of re-running into the same dead end.
  hash -r 2>/dev/null
  major="$(node_major_version)"
  if [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
    err "Node.js is still unusable after installing: $(node_problem "$major")"
    info "Open a NEW shell first (PATH only refreshes for new processes) and re-run."
    info "If you manage Node with a version manager:"
    info "  nvm install $MIN_NODE_MAJOR && nvm use $MIN_NODE_MAJOR   /   fnm use $MIN_NODE_MAJOR"
    info "Otherwise uninstall any old Node install and re-run setup."
    die "Node.js >= $MIN_NODE_MAJOR is required."
  fi
  ok "Node.js $(node -v) is now available."
}

# -----------------------------------------------------------------------------
# Phase 1 - prerequisites
# -----------------------------------------------------------------------------
check_prereqs() {
  step "Checking prerequisites"

  # --- Node.js ---------------------------------------------------------------
  ensure_node

  # --- npm -------------------------------------------------------------------
  if command -v npm >/dev/null 2>&1; then
    ok "npm v$(npm -v)"
  else
    die "npm is missing. It ships with Node.js - reinstall Node, or see: $(node_install_hint)"
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
  local dir="$1" label="$2" sentinel="$3"

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
  die "Cannot continue without $label dependencies."
}

install_dependencies() {
  step "Installing dependencies"
  install_deps "$BACKEND_DIR"  "backend"  "express"
  install_deps "$FRONTEND_DIR" "frontend" "react-scripts"
}

# -----------------------------------------------------------------------------
# Phase 5 - seed (opt-in, destructive)
# -----------------------------------------------------------------------------
run_seed() {
  step "Seeding demo data"
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
  else
    die "Seeding failed."
  fi
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

print_setup_summary() {
  local seeded="no"
  [ "$DO_SEED" = "1" ] && seeded="yes"

  cat <<SUMMARY

$(printf '%s%s  Setup complete - nothing was started%s' "$C_GREEN" "$C_BOLD" "$C_RESET")

    Database   ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}
    Backend    .env written, dependencies installed
    Frontend   dependencies installed
    Seeded     ${seeded}

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
    do_start_foreground_backend
    exit 0
  fi

  do_start
  print_summary
}

main "$@"
