# JasaSane Corp

A full-stack membership registration system with two-factor authentication (2FA). Users register with a phone number and password, log in via OTP verification, and gain the ability to register and manage member records. Any registered user can add members with their personal details, location, and profile image.

Built with:

- **Frontend**: React 18 (React Router v6, Axios), Create React App
- **Backend**: Express.js (Node.js)
- **Database**: PostgreSQL (`pg` pool)
- **Auth**: bcrypt (password hashing), jsonwebtoken (JWT), crypto (OTP generation)

## Features

### Authentication
- User registration with name, phone, and password
- Password-based login that generates a 6-digit OTP
- OTP delivered to the server console (simulated SMS; no SMS provider)
- Split 6-input OTP entry with auto-focus, backspace navigation, and paste support
- Single-use, expiring OTPs (5 minutes, configurable) validated against the database
- JWT-based authentication guarding protected routes
- Protected dashboard showing the authenticated user's profile with logout
- Forgot password flow that sends a reset OTP to the server console
- Persistent sessions via localStorage token + profile refresh

### Member Registration
- Register members with first name, last name, email address, and profile image
- Hierarchical location selection (Country → Province → City → Barangay)
- Edit and delete member records
- Role-based access: Admin sees all members, Regular users see only their own
- Profile image upload with preview

## How It Works

1. User registers with name, phone, and password (bcrypt-hashed).
2. User logs in with phone + password → the backend generates a 6-digit OTP, stores it in the `otps` table, and logs it to the server console.
3. User enters the OTP → the backend validates it (must be unused and unexpired), marks it used, and issues a JWT.
4. The JWT authorizes access to protected endpoints (e.g., `/profile`, `/records`), which the frontend uses to display the dashboard.
5. Any registered user can navigate to "Manage Records" and register new members by providing their first name, last name, email, location, and optional profile image.
6. Admin users can view and manage all member records; regular users can only view and manage their own records.

## Project Structure

```
membership-app/
├── setup.sh                           # One-command setup (macOS / Linux / WSL / Git Bash)
├── setup.ps1                          # One-command setup (Windows PowerShell)
├── setup.bat                          # Launcher for Command Prompt: picks pwsh → powershell → Git Bash
├── backend/
│   ├── scripts/seed.js              # Seeds demo users and records
│   ├── src/
│   │   ├── config/db.js              # PostgreSQL pool
│   │   ├── controllers/
│   │   │   ├── authController.js     # register/login/verifyOTP/getProfile/updateProfile
│   │   │   ├── recordController.js   # CRUD operations for member records
│   │   │   ├── locationController.js # Country/province/city/barangay data
│   │   │   └── userController.js     # List all users (admin)
│   │   ├── data/locations.json       # Philippine location data
│   │   ├── middleware/
│   │   │   ├── auth.js               # JWT verification guard
│   │   │   └── role.js               # Role-based access control
│   │   ├── models/init.js            # Auto-creates users, otps, records tables
│   │   ├── routes/
│   │   │   ├── auth.js               # /api/auth routes
│   │   │   ├── records.js            # /api/records routes
│   │   │   ├── locations.js          # /api/locations routes
│   │   │   └── users.js              # /api/users routes (admin)
│   │   ├── utils/
│   │   │   ├── otpGenerator.js       # Cryptographically secure 6-digit OTP
│   │   │   └── uploads.js            # File upload configuration
│   │   └── server.js                 # Express app entry point
│   ├── uploads/                      # Uploaded profile images
│   ├── .env / .env.example           # Environment configuration
│   └── package.json
└── frontend/
    ├── build/                        # Production build output
    ├── public/
    │   └── index.html
    ├── src/
    │   ├── components/
    │   │   ├── BrandHeader.jsx       # App header/branding
    │   │   ├── Dashboard.jsx         # User profile & navigation
    │   │   ├── EditProfileModal.jsx  # Edit user profile
    │   │   ├── ForgotPassword.jsx    # Password reset flow
    │   │   ├── LoginForm.jsx         # Phone + password login
    │   │   ├── Modal.jsx             # Reusable modal component
    │   │   ├── OtpHint.jsx           # OTP helper hint text
    │   │   ├── OTPVerification.jsx   # 6-digit OTP entry
    │   │   ├── RecordFormModal.jsx   # Create/edit member form
    │   │   ├── RecordsList.jsx       # Member records table
    │   │   ├── RegisterForm.jsx      # User registration
    │   │   ├── ResendOtpButton.jsx   # Resend OTP button
    │   │   └── UserFilterDropdown.jsx# Filter records by user
    │   ├── context/AuthContext.jsx   # Auth state + token persistence
    │   ├── pages/
    │   ├── services/api.js           # Axios client with auth interceptor
    │   ├── App.js                    # Routing + protected/public route guards
    │   └── index.js
├── logs/                              # Runtime logs + pid files (gitignored, created by the setup script)
```

## Prerequisites

- Node.js (v18+; v18 and v20 are end-of-life, so prefer v22 or v24)
- PostgreSQL (v14+)
- GNU Make — only needed for the `make` targets such as `make opencode`. See [Installing GNU Make](#installing-gnu-make).

## Setup

### Automated Setup (recommended)

Three scripts ship with the repo. They check prerequisites, create the
database, generate `backend/.env`, install dependencies and (on request) seed the
demo data - then stop. They do **not** start the app; you run it yourself
afterwards (or pass `--start`).

| Platform | Command |
| -------- | ------- |
| **Windows Command Prompt** | `setup.bat` |
| Windows (PowerShell) | `pwsh -File setup.ps1` |
| Windows (old PowerShell 5.1) | `powershell -ExecutionPolicy Bypass -File setup.ps1` |
| macOS, Ubuntu/Debian, other Linux | `./setup.sh` |
| WSL or Git Bash on Windows | `./setup.sh` |

On Command Prompt, `setup.bat` is a thin launcher: it picks an engine
(PowerShell 7, then Windows PowerShell 5.1, then Git Bash) and hands your
arguments straight to `setup.ps1` or `setup.sh`. It contains no setup logic of
its own. On macOS and Linux, just run `./setup.sh` directly.

```powershell
:: Command Prompt or PowerShell - the same command works in both
setup.bat --db-password=your_password
```

Because `setup.bat` forwards your arguments verbatim, **every switch in the
table below works through it unchanged**, and `setup.bat --help` shows the same
help. On a fresh Windows machine it will pick `setup.ps1`, so
[the PowerShell behaviour is what you get](#windows-vs-macoslinux).

Make the shell script executable once after cloning:

```bash
chmod +x setup.sh
```

#### What the setup script does, in order

`setup.bat` (via `setup.ps1`) and `./setup.sh` both run these steps:

1. Check Node.js — offer to install it if it is missing **or too old**
2. Check PostgreSQL — start its Windows service if it is stopped, offer to
   install it if it is missing
3. Configure `backend/.env` — prompted for only when it is missing
4. Create the database named in `backend/.env`
5. `npm ci` in `backend`
6. Seed the demo data — **opt-in via `--seed`, destructive, asks you to type `SEED`**
7. `npm ci` in `frontend`

**Setup asks you nothing when everything is already in place.** A re-run on a
fully prepared machine prints status and moves on: no install prompts, no `.env`
re-entry, no seed confirmation. Questions appear only for what is genuinely
missing, or when you explicitly ask to change something (`--seed`,
`--reconfigure-env`).

The seed sits between the two installs on purpose: it needs `bcrypt` from the
backend dependencies, and it creates the tables itself through
`backend/src/models/init.js`, so the backend does not have to be running yet.

`setup.sh` and `setup.ps1` share the same options. PowerShell accepts both the
POSIX style and its own, so commands are portable across every platform:

```
--seed             -Seed
--start            -Start
--db-name=x        -DbName x
--reconfigure-env  -ReconfigureEnv
--opencode         -OpenCode
```

#### Windows vs macOS/Linux

`setup.ps1` and `setup.sh` still differ in how an existing `backend/.env` is
handled. The differences below are real:

| | `setup.bat` / `setup.ps1` (Windows) | `setup.sh` (macOS, Linux, WSL) |
| --- | --- | --- |
| Seeds on a plain run | **No** — pass `--seed` | **No** |
| Opt out | `--no-seed` (redundant; the default) | Not available |
| Force on | `--seed` | `--seed` |
| `backend/.env` | Prompts for **every** key when creating it | Prompts only for `DB_USER` and `DB_PASSWORD` |
| `JWT_SECRET` | Prompted; type `random` to generate one, or keep the default and get a warning | Always generated automatically, no prompt |
| Existing `backend/.env` | Shown (secrets masked) and **reused as-is**; `--reconfigure-env` re-asks every key and rewrites it | Reused as-is and never rewritten |
| Node.js unusable | Records skipped steps and continues | Stops the run |
| PostgreSQL service stopped | Started automatically, then re-probed | Not applicable (no service) |

Neither script ever rewrites an existing `backend/.env` unless you explicitly
ask it to.

| Option | What it does |
| ------ | ------------ |
| *(none)* | Full setup only. **Starts nothing.** |
| `--start` | Also start the backend and frontend in the background |
| `--dev` | Run the backend with nodemon in the foreground (implies `--start`; the frontend stays stopped) |
| `--seed` | Load demo data. Opt-in — **not** run by a plain `setup.bat`. Destructive; asks you to type `SEED` |
| `--no-seed` | Skip the seed step (this is already the default; kept for clarity in scripts) |
| `--reconfigure-env` | Re-ask every `backend/.env` value and rewrite the file, even though it exists |
| `--opencode` | Report the OpenCode CLI version, or offer to install it globally via npm. Also writes `opencode.json` if it is missing. See [OpenCode](#opencode) |
| `--status` | Report what is currently running |
| `--stop` | Stop both servers |
| `--logs` | Tail both logs (the OTP is printed here) |
| `--clean` | Stop and remove `node_modules` and logs |
| `--db-name=NAME` | Database to create/use (default `jasasane_app`) |
| `--db-user=USER` | PostgreSQL user (default: prompted, pre-filled with `postgres`) |
| `--db-password=PASS` | PostgreSQL password (default: prompts, input hidden) |
| `--db-host=HOST` | PostgreSQL host (default `localhost`) |
| `--db-port=PORT` | PostgreSQL port (default `5432`) |
| `--trust-local-auth` | Skip the password prompt and credential check. Only for `trust`/`peer` auth in `pg_hba.conf`; leaves `DB_PASSWORD` empty |
| `--port=PORT` | Backend port (default `5000`) |
| `--frontend-port=PORT` | Frontend port (default `3000`) |
| `--yes` | Assume yes for every prompt, for non-interactive runs |
| `--help` | Show the built-in help |

Examples:

```bash
# First-time setup. Prepares everything, starts nothing.
./setup.sh --db-password=your_password

# Same, but also leave both servers running in the background
./setup.sh --db-password=your_password --start

# Windows: first-time setup, same thing through the launcher
setup.bat --db-password=your_password

# Re-run later: nothing is already in place, so setup asks nothing
setup.bat

# Load the demo data (destroys existing data, confirms with SEED)
setup.bat --seed

# Change the database credentials after the first run
setup.bat --reconfigure-env

# Fully unattended (CI, or a machine where you already know the password)
setup.bat --yes --db-user=postgres --db-password=postgres
```

#### How `backend/.env` is configured

On Windows (`setup.bat` / `setup.ps1`), setup prompts for **every** key **when
it has to create the file**. Press Enter at each prompt to accept the default
shown in brackets:

| Key | Default | Notes |
| --- | ------- | ----- |
| `PORT` | `5000` | Changing this also requires editing `frontend/src/services/api.js` — the script warns you |
| `DB_HOST` | `localhost` | |
| `DB_PORT` | `5432` | |
| `DB_NAME` | `jasasane_app` | Note `.env.example` ships `otp_auth_db` instead |
| `DB_USER` | `postgres` | |
| `DB_PASSWORD` | *(none)* | The only key with no default — it must be typed, hidden input |
| `JWT_SECRET` | `your_super_secret_key_change_this` | Type **`random`** to have setup generate a 48-byte secret for you |
| `OTP_EXPIRY_MINUTES` | `5` | No switch exists for this or the two below; edit the file |
| `MAX_LOGIN_ATTEMPTS` | `3` | Failed logins before a non-admin user is locked out |
| `LOCKOUT_MINUTES` | `15` | How long that lockout lasts |

Two things to know:

- **Leaving the default `JWT_SECRET` prints a warning.** That value is published
  in this README and in `.env.example`, so anyone who knows it can forge login
  tokens. Type `random` at the prompt to avoid it. (`setup.sh` never offers the
  default — it generates a secret every time.)
- **An existing `backend/.env` is reused, silently.** Setup prints the current
  values (with `DB_PASSWORD` and `JWT_SECRET` masked) and moves on — it never
  asks *keep these values, or re-enter them?* and never rewrites the file on its
  own. Pass `--reconfigure-env` to be prompted for every key again and have the
  file rewritten. `--db-*` switches still win over the file.

Once setup finishes, start the app in two terminals:

```bash
cd backend  && npm run dev     # http://localhost:5000
cd frontend && npm start       # http://localhost:3000
```

Then open **http://localhost:3000**. (If you skipped the seed, the first backend
run creates the `users`, `otps` and `records` tables — there is no migration step.)

**About the OTP.** This project simulates SMS: the six-digit code is printed to
the **backend** console and is not sent anywhere. When you run in the background,
read it from the log:

```bash
grep -i otp logs/backend.log | tail -1     # macOS / Linux
```

```powershell
Select-String -Path logs\backend.log -Pattern 'OTP' | Select-Object -Last 1   # Windows
```

Demo logins once the seed has run (password `Password@123` for all three):

| Role    | Phone        |
| ------- | ------------ |
| Admin   | `09999999999` |
| Regular | `09111111111` |
| Regular | `09222222222` |

> **`--seed` is destructive.** `backend/scripts/seed.js` deletes every row in
> `records` and `otps`, and deletes every user except the three phones above.
> It still asks you to type `SEED` to confirm. It is **opt-in on every
> platform**, so a plain `setup.bat` leaves your data alone. Never point
> `--seed` at a database you care about.

What the script does **not** do:

- It never starts the backend or frontend unless you pass `--start` or `--dev`.
- It never overwrites an existing `backend/.env`. It reuses the file and prints
  the values; only `--reconfigure-env` rewrites it. See
  [How `backend/.env` is configured](#how-backendenv-is-configured).
- It never installs anything without asking first — and it never offers to
  install something that is already installed. Node, npm and `psql` are probed
  on `PATH` **and** in their well-known install directories, because
  PostgreSQL's installer deliberately leaves `C:\Program Files\PostgreSQL\<version>\bin`
  off `PATH`. When something really is missing, setup prints the install command
  for your platform and waits for confirmation; with no package manager it
  prints a download URL instead.
- It never seeds unless you pass `--seed`.
- It does not always create the tables. The seed creates them, and otherwise the
  backend creates them on its first boot. It always creates the *database*.
- It never guesses your password. If `pg_hba.conf` is set to `trust` rather than
  `md5`/`scram`, pass `--trust-local-auth` and it will skip the prompt. It needs
  the `psql` client on `PATH` either way, because that is what creates the
  database.

#### If Node or npm is missing

`setup.ps1` (and therefore `setup.bat`) **does not abort** when it cannot find or
use Node. Every step that needs `npm` — the two installs, the seed, `--start` —
is recorded as skipped, everything else still runs, and the run ends with a
`SETUP INCOMPLETE` block listing each skipped step and the reason:

```
  SETUP INCOMPLETE
  Some steps could not run:
    - npm-dependent steps  (npm was not found)
```

Fix the cause and re-run: it resumes where it left off and re-uses the existing
`backend/.env`. `setup.sh` has no equivalent recovery — it stops on a missing or
too-old Node.

An old-but-working Node is handled differently: if `node` runs but is below
version 18, setup warns that `npm` may fail on it and continues anyway, so the
npm steps are still attempted rather than skipped.

Notes on the Windows installer path, should you hit it:

- Node.js and PostgreSQL are installed with **winget** (or **choco**), passing
  `--accept-package-agreements --accept-source-agreements` so the install cannot
  stall on an interactive prompt that looks like a hang.
- winget draws its own progress bar, which only renders because the installer is
  launched attached to your console. A UAC prompt is expected for a machine-wide
  install.
- "Already installed" is treated as success, not failure — including
  winget's `0x8A15002B`, and the `3010`/`1641` "succeeded, reboot pending" codes.
- With no `winget` and no `choco`, setup prints a download URL instead of trying
  to run one as a command.
- If Node is installed but still not found, setup re-reads `PATH` from the
  registry (without discarding your session-only entries) and then probes the
  usual install directories — `%ProgramFiles%\nodejs`,
  `%LOCALAPPDATA%\Programs\nodejs`, the nvm folders, and so on.
- `psql` gets the same treatment, and it matters more often: PostgreSQL installs
  to `%ProgramFiles%\PostgreSQL\<version>\bin` and the installer does **not** add
  that directory to `PATH`. Setup probes those directories (newest version first)
  before concluding PostgreSQL is missing, so an installed-but-off-`PATH`
  PostgreSQL is used rather than offered for installation again.
- If PostgreSQL is installed but its Windows service is stopped, setup starts it
  (`postgresql-*`, newest first) and re-probes instead of asking what to do. Only
  if that fails — usually an Administrator rights problem — does it print the
  manual `net start` command.

Runtime files (`backend.log`, `frontend.log`, `*.pid`) are written to `logs/`,
which is gitignored. They only appear if you start the app with `--start`.

> **Note on Command Prompt:** `cmd.exe` re-parses forwarded arguments, so a
> password containing `&`, `^`, `|`, `<` or `>` will be mangled when passed
> through `setup.bat`. For those, run the script directly in PowerShell
> (`.\setup.ps1 --db-password="..."`) or in Git Bash, which forward arguments
> safely. The interactive prompt is always the safest way to set it.

### Manual Setup

The original step-by-step instructions follow, unchanged.

#### Step 0: Check Prerequisites

Make sure you have the following installed on your machine:

```bash
node --version    # Node.js v18 or newer
npm --version     # npm comes with Node.js
psql --version    # PostgreSQL v14 or newer
```

PostgreSQL must be installed and running locally on port `5432` before continuing.

#### Step 1: Set Up the Database

Create the database (run once):

```bash
psql -U postgres -h localhost -c "CREATE DATABASE database_name;"
```

> Tables (`users`, `otps`, `records`) are created automatically when the backend server starts, so there is no need to run any migration scripts.

#### Step 2: Configure the Backend Environment

The backend needs a `.env` file to know how to connect to the database and sign JWTs. Start by copying the provided template:

```bash
cd backend
cp .env.example .env
```

Now open `backend/.env` and update it to match your local setup:

| Variable             | Description                                              | Example                          |
| -------------------- | -------------------------------------------------------- | -------------------------------- |
| `PORT`               | Port the backend server runs on                          | `5000`                           |
| `DB_HOST`            | PostgreSQL host                                          | `localhost`                      |
| `DB_PORT`            | PostgreSQL port                                          | `5432`                           |
| `DB_NAME`            | Name of the database you created in Step 1               | `database_name`                  |
| `DB_USER`            | Your PostgreSQL username                                 | `postgres`                       |
| `DB_PASSWORD`        | Your PostgreSQL password                                 | `your_db_password`               |
| `JWT_SECRET`         | Secret used to sign authentication tokens (change this!) | `some_long_random_secret_string` |
| `OTP_EXPIRY_MINUTES` | How long a generated OTP remains valid (in minutes)      | `5`                              |

You **must** set `DB_USER` and `DB_PASSWORD` to the credentials of your local PostgreSQL, and change `JWT_SECRET` to your own secret string.

#### Step 3: Install and Run the Backend

```bash
cd backend
npm install
npm run dev
```

`npm run dev` starts the backend with auto-reload (nodemon). It runs on `http://localhost:5000`.

> **Keep this terminal open.** The OTP is simulated — it is printed to this backend terminal's console (not sent via SMS), so you will need to read it from here when you log in.

Available backend commands:

| Command        | Description                           |
| -------------- | ------------------------------------- |
| `npm run dev`  | Development server with auto-reload   |
| `npm start`    | Run the backend normally (production) |
| `npm run seed` | Populate the database with demo users |

#### Step 4: Install and Run the Frontend

Open a **second terminal** and run:

```bash
cd frontend
npm install
npm start
```

`npm start` runs the React app on `http://localhost:3000`. It proxies API calls to the backend at `http://localhost:5000` (configured via `proxy` in `package.json`).

#### Step 5 (Optional): Seed Demo Data

To get started quickly with pre-created test users, run the seed script in the backend folder:

```bash
cd backend
npm run seed
```

This creates demo users (all with the password `Password@123`), so you can log in right away.

#### Accessing the App

With both terminals running, open `http://localhost:3000` in your browser.

## Installing GNU Make

`make` drives the OpenCode workflow and the other convenience targets in the
`Makefile`. GNU Make is preinstalled on macOS and most Linux distributions; on
Windows it is not.

Check whether you already have it:

```bash
make --version   # "GNU Make 4.x" or similar
```

### Linux

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y make

# Fedora / RHEL / CentOS
sudo dnf install -y make

# Arch (make ships in the base-devel group)
sudo pacman -S make

# Alpine
sudo apk add make

# openSUSE
sudo zypper install -y make
```

### macOS

`make` comes with the Xcode Command Line Tools, which macOS offers to install
on first use. To install it directly:

```bash
xcode-select --install
```

A dialog appears; click **Install**. If it reports the tools are already
installed, you are done:

```bash
make --version
```

Optionally, for GNU Make 4.x instead of Apple's 3.81:

```bash
brew install make    # installs as `gmake`
```

### Windows

Windows has no built-in `make`. **WSL is the recommended route**, because the
`Makefile` recipes are POSIX shell and run unchanged inside WSL:

```powershell
# One-time: install WSL with Ubuntu (restart if prompted)
wsl --install -d Ubuntu

# Then, inside the WSL shell
sudo apt-get update && sudo apt-get install -y make
```

Clone or open the project inside the WSL filesystem (`\\wsl$`) and run
`make opencode` from there.

Native Windows alternatives, if you would rather not use WSL:

```powershell
# winget (package id is ezwinports.make; the old GnuWin32.Make was removed)
winget install -e --id ezwinports.make

# Chocolatey
choco install make -y

# Scoop
scoop install make
```

> **Caveat:** the `Makefile` has no `SHELL` override, so Windows-native `make`
> runs recipes through `cmd.exe`, where the POSIX syntax in the `opencode`
> target will fail. If you hit this, use WSL, or set a POSIX shell for make:
>
> ```powershell
> make SHELL="C:\Program Files\Git\bin\bash.exe" opencode
> ```

Open a **new terminal** after any Windows install so the updated `PATH` is
picked up.

## OpenCode

This project has an [OpenCode](https://opencode.ai) workspace: a root
`opencode.json` that sets the model, the default agent and the tool
permissions, plus a Makefile target that launches it.

```bash
make opencode
```

Run it from the repository root. It installs the CLI on demand, then starts
OpenCode, which picks up `opencode.json` automatically. The target starts
nothing else — the backend and frontend still need `make run` (or
`./setup.sh --start`) if you want the app up alongside it.

| Step | What happens |
| ---- | ------------ |
| `command -v opencode` | If the CLI is missing, installs `opencode-ai@latest` globally via npm |
| `opencode` | Launches the TUI in this directory using `opencode.json` |

### Installing and checking the CLI

`opencode.json` is **not** committed — it is listed in `.gitignore`, so it stays a
local file and its model and permission choices stay yours. Setup will create it
for you when it is missing:

```bash
./setup.sh --opencode          # Linux / macOS / Git Bash
setup.bat --opencode           # Windows
```

`--opencode` is opt-in and is a **no-op for the app itself** — nothing in
`backend/` or `frontend/` needs the CLI. It only:

- **reports** the installed version when `opencode` is already on `PATH`
  (no prompt at all), or
- **asks** before running `npm install --global opencode-ai@latest`, and
- writes `opencode.json` only when that file does not exist — an existing one is
  never overwritten.

It never launches OpenCode for you; use `make opencode` or run `opencode`
yourself when you want the TUI. `./setup.sh --status` reports the CLI version
alongside the rest of the environment.

> **Windows:** a global npm install writes its shim to the npm global prefix,
> which the Node.js installer does *not* put on `PATH`. Setup re-probes for
> `opencode.cmd` in `%APPDATA%\npm`, `%LOCALAPPDATA%\npm` and
> `C:\Program Files\nodejs` and adds it for the rest of the run. If it still is
> not callable, add that directory to `PATH` and open a **new** terminal.

### Configuration

`opencode.json` sets:

- **Model** - `opencode/big-pickle`
- **Default agent** - `build`
- **Permissions** - `"*": "ask"` with read-only tools (`read`, `view`, `grep`,
  `glob`, `webfetch`, `websearch`, `todowrite`, `question`) allowed, and `edit`,
  `bash`, `task`, `skill`, `external_directory` prompting first. So OpenCode
  asks before it writes files, runs commands, or reaches outside the workspace.

A local `.opencode/` directory is picked up too if present (it is gitignored, so
it stays local): `agents/` for custom subagents, `skills/` for project skills,
`docs/` for reference material.

### Notes

- Requires GNU Make and Node.js/npm. `make` is not preinstalled on Windows — see
  [Installing GNU Make](#installing-gnu-make) above.
- `make opencode` never touches the database or the running app.
- A global npm install under `C:\Program Files\nodejs` needs an Administrator
  prompt; otherwise run it in a terminal where `npm prefix -g` is writable.

## Troubleshooting

| Problem                                       | Solution                                                                                                                                                    |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ECONNREFUSED` / PostgreSQL connection failed | Make sure PostgreSQL is installed and running on port `5432`, and that `DB_USER` / `DB_PASSWORD` in `backend/.env` match your local PostgreSQL credentials. |
| Port `3000` or `5000` already in use          | Either stop the process using that port, or change `PORT` in `backend/.env` and the `proxy` in `frontend/package.json`.                                     |
| No OTP received after login                   | The OTP is simulated and printed to the **backend terminal** console. Check the terminal running `npm run dev` (Step 3), or `logs/backend.log` when started via the setup script. |
| Tables not created                            | Tables are created automatically when the backend starts. If they are missing, restart the backend.                                                         |
| Frontend loads but every API call fails       | `frontend/src/services/api.js` hardcodes `http://localhost:5000`. If you changed `PORT` in `backend/.env`, edit those URLs too - the `proxy` field in `frontend/package.json` is not used by the app. |
| Windows firewall prompt on first run          | Allow Node.js on the private network when prompted, otherwise the browser cannot reach the backend on port `5000`.                                          |
| `SETUP INCOMPLETE` printed after `setup.bat`   | Node.js or npm could not be used, so those steps were skipped and everything else still ran. Fix Node, then re-run — it resumes and re-uses `backend/.env`. See [If Node or npm is missing](#if-node-or-npm-is-missing). |
| Node.js installed but setup says it is still not usable | A stale `PATH`, or a version manager / IDE shim shadowing it. Open a **new** terminal and re-run; setup already re-reads `PATH` from the registry and probes the usual install directories. With `nvm`, run `nvm use 22` (or 24) in the same terminal first. |
| Setup offers to install PostgreSQL that is already installed | The installer never adds `C:\Program Files\PostgreSQL\<version>\bin` to `PATH`. Setup probes those directories automatically; if it still offers an install, your install is somewhere else — add its `bin` to `PATH` and re-run. |
| `PostgreSQL is not answering on localhost:5432 after 30s` | The service did not start automatically (needs an Administrator prompt) or is not on port 5432. Run `net start postgresql-x64-16` from an Administrator prompt, or set `DB_PORT` in `backend/.env` / pass `--db-port`. |
| `setup.bat` mangles the password              | `cmd.exe` re-parses `&`, `^`, `\|`, `<`, `>` in forwarded arguments. Use the interactive prompt, or run `.\setup.ps1 --db-password="..."` in PowerShell. |
| `react-scripts` fails to compile with `digital envelope routines::unsupported` | `react-scripts` 5.0.1 predates OpenSSL 3. The resolved webpack (5.110.x) uses a WebAssembly MD4 so this normally does **not** occur; if it does, set `NODE_OPTIONS=--openssl-legacy-provider` before `npm start`. |

## Usage

1. Open `http://localhost:3000`
2. Register with a full name, phone number, and password
3. Login with phone + password
4. **Check the backend console** for the OTP (simulates SMS)
5. Enter the 6-digit OTP on the verification screen
6. Access the protected dashboard and log out when done

### Registering Members

1. Log in and navigate to the dashboard
2. Click **Manage Records**
3. Click **+ Add Record** to open the member registration form
4. Enter the member's first name, last name, email address, and optional profile image
5. Select the location using the cascading dropdowns (Country → Province → City → Barangay)
6. Click **Create** to save the member record
7. Edit or delete existing members using the **Edit** and **Delete** buttons in the records table

> Any registered user has the power to register new members. Admin users can view and manage all member records, while regular users can only manage the members they created.

## API Endpoints

### Authentication
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/health`          | Server health check                       | No                 |
| POST   | `/api/auth/register`   | Register new user (name, phone, password) | No                 |
| POST   | `/api/auth/login`      | Login, sends OTP to console               | No                 |
| POST   | `/api/auth/verify-otp` | Verify OTP, returns JWT for valid access  | No                 |
| POST   | `/api/auth/forgot-password` | Request password reset OTP (sent to console) | No           |
| POST   | `/api/auth/reset-password`  | Verify reset OTP and set new password    | No                 |
| GET    | `/api/auth/profile`    | Get authenticated user profile            | Yes (Bearer token) |
| PUT    | `/api/auth/profile`    | Update user profile (with image upload)   | Yes (Bearer token) |

### Member Records
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/records`         | Get all records (admin) or own records    | Yes (Bearer token) |
| GET    | `/api/records/:id`     | Get record by ID                          | Yes (Bearer token) |
| POST   | `/api/records`         | Create new member record                  | Yes (Bearer token) |
| PUT    | `/api/records/:id`     | Update member record                      | Yes (Bearer token) |
| DELETE | `/api/records/:id`     | Delete member record                      | Yes (Bearer token) |

### Locations (Philippine Address Data)
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/locations/countries` | Get list of countries                 | No                 |
| GET    | `/api/locations/provinces/:countryId` | Get provinces by country     | No                 |
| GET    | `/api/locations/cities/:provinceId` | Get cities by province         | No                 |
| GET    | `/api/locations/barangays/:cityId` | Get barangays by city           | No                 |

### Users
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/users`           | Get list of all users (admin only)        | Yes (Bearer token, admin) |

## Configuration (.env)

```
PORT=5000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=database_name
DB_USER=postgres
DB_PASSWORD=your_password
JWT_SECRET=your_secret_key
OTP_EXPIRY_MINUTES=5
```

## Notes

- OTP is logged to the server console (an SMS provider integration can replace this)
- JWT expires in 1 hour
- OTPs are single-use and expire after 5 minutes
- Passwords are hashed with bcrypt (10 salt rounds)
- For production, use environment variables for secrets and add rate limiting
