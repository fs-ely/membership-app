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
database, generate `backend/.env`, install dependencies and seed the demo data -
then stop. They do **not** start the app; you run it yourself afterwards (or
pass `--start`).

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
2. Check PostgreSQL — offer to install it if it is missing
3. Configure `backend/.env`
4. Create the database named in `backend/.env`
5. `npm ci` in `backend`
6. Seed the demo data — **destructive, asks you to type `SEED`**
7. `npm ci` in `frontend`

Steps 1, 2, 4, 5 and 7 behave the same on every platform. Steps 3 and 6 do not —
see [Windows vs macOS/Linux](#windows-vs-macoslinux).

The seed sits between the two installs on purpose: it needs `bcrypt` from the
backend dependencies, and it creates the tables itself through
`backend/src/models/init.js`, so the backend does not have to be running yet.

`setup.sh` and `setup.ps1` share the same options. PowerShell accepts both the
POSIX style and its own, so commands are portable across every platform:

```
--seed        -Seed
--no-seed     -NoSeed
--start       -Start
--db-name=x   -DbName x
```

#### Windows vs macOS/Linux

`setup.ps1` and `setup.sh` drifted apart in the last round of changes. The
differences below are real, so read this before you rely on the seed:

| | `setup.bat` / `setup.ps1` (Windows) | `setup.sh` (macOS, Linux, WSL) |
| --- | --- | --- |
| Seeds on a plain run | **Yes, by default** | **No** |
| Opt out | `--no-seed` | Not available |
| Force on | `--seed` | `--seed` |
| `backend/.env` | Prompts for **every** key | Prompts only for `DB_USER` and `DB_PASSWORD` |
| `JWT_SECRET` | Prompted; type `random` to generate one, or keep the default and get a warning | Always generated automatically, no prompt |
| Existing `backend/.env` | Shown (secrets masked), then *keep or re-enter?* | Reused as-is and never rewritten |
| Node.js unusable | Records skipped steps and continues | Stops the run |

On Windows, pass `--no-seed` when you want a database with your own data. On
macOS and Linux, pass `--seed` when you want the demo data.

| Option | What it does |
| ------ | ------------ |
| *(none)* | Full setup only. **Starts nothing.** |
| `--start` | Also start the backend and frontend in the background |
| `--dev` | Run the backend with nodemon in the foreground (implies `--start`; the frontend stays stopped) |
| `--seed` | Load demo data. Already the default on Windows — this only forces it on there |
| `--no-seed` | Skip the seed step. Windows only; see [the table above](#windows-vs-macoslinux) |
| `--status` | Report what is currently running |
| `--stop` | Stop both servers |
| `--logs` | Tail the logs (the OTP is printed here) |
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
# On macOS/Linux add --seed if you want the demo data; on Windows it seeds already.
./setup.sh --db-password=your_password

# Same, but also leave both servers running in the background
./setup.sh --db-password=your_password --start

# Windows: set up without wiping/creating demo data
setup.bat --db-password=your_password --no-seed

# Reset the database to the three demo users and 10 sample records
setup.bat --seed

# Fully unattended (CI, or a machine where you already know the password)
setup.bat --yes --db-user=postgres --db-password=postgres
```

#### How `backend/.env` is configured

On Windows (`setup.bat` / `setup.ps1`), setup prompts for **every** key rather
than copying `.env.example` blindly. Press Enter at each prompt to accept the
default shown in brackets:

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
- **An existing `backend/.env` is never silently replaced.** Setup prints the
  current values (with `DB_PASSWORD` and `JWT_SECRET` masked) and asks *Keep
  these values, or re-enter them?* Answer `n` to be prompted again — that is the
  only case in which setup rewrites the file. `setup.sh` goes further and never
  rewrites an existing `.env` at all.

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
> It still asks you to type `SEED` to confirm, and `--no-seed` skips it entirely.
> Note that on Windows it runs **by default**, so a plain `setup.bat` will reset
> your database. Never point it at a database you care about.

What the script does **not** do:

- It never starts the backend or frontend unless you pass `--start` or `--dev`.
- It never overwrites an existing `backend/.env` behind your back — on Windows
  it asks first, on macOS/Linux it does not rewrite at all. See
  [How `backend/.env` is configured](#how-backendenv-is-configured).
- It never installs anything without asking first. If Node.js or PostgreSQL is
  missing it prints the install command for your platform and waits for
  confirmation; with no package manager it prints a download URL instead.
- It never seeds on macOS/Linux unless you ask it to. On Windows it seeds by
  default — see [Windows vs macOS/Linux](#windows-vs-macoslinux).
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

The repo ships with an [OpenCode](https://opencode.ai) workspace: a root
`opencode.json` and a single Makefile target that launches it.

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
