<#
.SYNOPSIS
    One-command setup for the JasaSane membership app (backend + frontend).

.DESCRIPTION
    backend  : Node.js + Express + PostgreSQL  ->  http://localhost:5000
    frontend : React 18 (Create React App)      ->  http://localhost:3000

    This script only prepares the machine: prerequisites, database,
    backend\.env and dependencies. It starts nothing. Pass -Start to launch
    both servers.

    Platforms : Windows 10/11 with Windows PowerShell 5.1 or PowerShell 7+.
                (macOS / Linux / WSL / Git Bash users should run setup.sh,
                 which takes the same flags.)

.EXAMPLE
    pwsh -File setup.ps1
    .\setup.ps1 -Seed
    .\setup.ps1 -Start
    .\setup.ps1 -Status
    .\setup.ps1 -Stop
#>

#Requires -Version 5.1

<#
    A param() block is required so the switches actually reach Parse-Args.
    Without it PowerShell collects them in the automatic $args variable, which
    Invoke-Main (a function, with its own $args) can never see - meaning every
    flag would be silently ignored and the full setup would always run.
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
$Root         = $PSScriptRoot
$BackendDir   = Join-Path $Root 'backend'
$FrontendDir  = Join-Path $Root 'frontend'
$LogDir       = Join-Path $Root 'logs'
$BackendLog   = Join-Path $LogDir 'backend.log'
$FrontendLog  = Join-Path $LogDir 'frontend.log'
$BackendPid   = Join-Path $LogDir 'backend.pid'
$FrontendPid  = Join-Path $LogDir 'frontend.pid'

$MinNodeMajor = 18
$MinPgMajor   = 14

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
$DbHost       = if ($env:DB_HOST)     { $env:DB_HOST }     else { 'localhost' }
$DbPort       = if ($env:DB_PORT)     { $env:DB_PORT }     else { '5432' }
$DbName       = if ($env:DB_NAME)     { $env:DB_NAME }     else { '' }
$DbUser       = if ($env:DB_USER)     { $env:DB_USER }     else { '' }
$DbPassword   = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { '' }
$JwtSecret    = if ($env:JWT_SECRET)  { $env:JWT_SECRET }  else { '' }
$OtpExpiryMinutes = '5'
$MaxLoginAttempts = '3'
$LockoutMinutes    = '15'
$ApiPort      = 5000
$FrontendPort = 3000

# True only when -Port was passed, so an explicit 5000 is not re-prompted for.
$script:PortGiven = $false
# Same idea for the database coordinates. Check-Prereqs waits for PostgreSQL
# before Ensure-Env reads backend/.env, so without these it would probe
# localhost:5432 regardless of where the .env says the database actually is.
$script:DbHostGiven = $false
$script:DbPortGiven = $false

$AssumeYes = $false
# Seeding is destructive, so it is opt-in on every platform. It used to default
# to $true here, which meant every plain `setup.bat` stopped to ask for the word
# SEED even on a machine that was already fully set up and had data worth
# keeping. setup.sh has always defaulted it off.
$DoSeed    = $false
$DoStart   = $false
$RunDev    = $false
$TrustLocalAuth = $false
# Re-enter every backend/.env key even though the file exists. Off by default, so
# an existing file is reused without asking.
$ReconfigureEnv = $false
# Check for / install the OpenCode CLI. Off by default: it is a global npm install
# that the app itself does not need, so it happens only when asked for.
$OpenCode = $false
$Mode      = 'setup'

# Toolchain state, decided once in Check-Prereqs and read by every step that
# shells out to node/npm. A missing Node must never abort the run - it only
# means the npm steps cannot be performed, so those are skipped and recorded
# here rather than guessed at.
$script:NodeReady = $true
$script:NpmReady  = $true
$script:Skipped   = @()

function Add-SkippedStep {
    # Records a step that could not run, for the SETUP INCOMPLETE report at the
    # end. An array rather than a List so it survives StrictMode 2.0 with no
    # method call on a possibly-null value.
    param([string]$Step, [string]$Reason)
    $script:Skipped += [pscustomobject]@{ Step = $Step; Reason = $Reason }
}

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
function Step  { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Info  { param([string]$Message) Write-Host "    $Message" }
function Ok    { param([string]$Message) Write-Host "    [ok] $Message" -ForegroundColor Green }
function Warn  { param([string]$Message) Write-Host "    [!]  $Message" -ForegroundColor Yellow }
function Note  { param([string]$Message) Write-Host "    [-]  $Message" -ForegroundColor Blue }
function Err   { param([string]$Message) Write-Host "    [!!] $Message" -ForegroundColor Red }
function Die   { param([string]$Message) Err $Message; exit 1 }

# -----------------------------------------------------------------------------
# Native command execution
# -----------------------------------------------------------------------------
function Get-CodeHex {
    # Converts a native command exit code to an 8-hex character string
    # (treating it as unsigned 32-bit). PowerShell 5.1 and 7 disagree on the
    # sign of large hex literals, so this avoids -eq comparisons against them.
    # [long], not [int]: the same code arrives signed (-1978335189) from
    # Start-Process and unsigned (2316632107) if it is ever computed or read
    # elsewhere, and an [int] parameter would reject the second form outright.
    param([long]$Code)
    $u = $Code
    if ($u -lt 0) { $u += 4294967296 }
    return $u.ToString('X8')
}

function Invoke-NativeQuiet {
    # Invoke-NativeQuiet -Exe <name> [-Rest @(<args>)]
    #   -> [pscustomobject]@{ Output = [string[]]; ExitCode = [int] }
    #
    # Every external tool in this script (node, psql, pg_isready, netstat, lsof,
    # ss, ps, icacls) goes through here, for one reason:
    #
    # In Windows PowerShell 5.1 - and in PowerShell 7.0/7.1 - redirecting a native
    # command's stderr with 2>$null does NOT merely discard it. Each stderr line is
    # wrapped in a NativeCommandError ErrorRecord, and because this script sets
    # $ErrorActionPreference = 'Stop' globally, the FIRST such line aborts the whole
    # run with an opaque error pointing at the command:
    #
    #     $raw = (node -p '...' 2>$null)   # -> setup.ps1:NNN char:13, NativeCommandError
    #
    # Upstream only stopped this in PowerShell 7.2. A tool that merely prints a
    # warning to stderr was therefore enough to kill setup.
    #
    # Redirecting nothing would also be safe, but then every warning a tool emits is
    # sprayed over the setup output, so we silence it here - safely:
    #   * $ErrorActionPreference is reassigned inside this function, which creates a
    #     FUNCTION-SCOPED variable. It cannot leak to the caller.
    #   * try/catch covers a command that fails to execute at all.
    #   * $LASTEXITCODE decides success, because exit code is the only reliable
    #     signal for a native command (stderr is not).
    param([string]$Exe, [string[]]$Rest = @())

    $ErrorActionPreference = 'SilentlyContinue'

    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Output = @(); ExitCode = -1 }
    }
    try {
        $out = @(& $Exe @Rest 2>$null)
        return [pscustomobject]@{ Output = @($out); ExitCode = $LASTEXITCODE }
    } catch {
        return [pscustomobject]@{ Output = @(); ExitCode = -1 }
    }
}

function Get-NodeVersionText {
    # -> the installed version as a printable string, for messages only.
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return 'not found' }
    $out = (Invoke-NativeQuiet -Exe node -Rest @('-v')).Output
    if ($out.Count -gt 0) { return $out[0] }
    return 'unknown'
}

function Test-InstallerSucceeded {
    # Decides whether an installer exit code means SUCCESS. A non-zero code from
    # winget/choco/msiexec does NOT reliably mean failure:
    #
    #   0x8A15002B (-1978335189) APPINSTALLER_CLI_ERROR_NO_APPLICABLE_INSTALLER
    #       winget returns this when the package is ALREADY INSTALLED - nothing to
    #       do, but reported as an error. Treating it as failure aborts setup even
    #       though the tool is present and working.
    #   3010 ERROR_SUCCESS_REBOOT_REQUIRED / 1641 ERROR_SUCCESS_REBOOT_INITIATED
    #       Windows Installer convention: the install SUCCEEDED, a reboot is
    #       pending. Node's MSI does this on some systems.
    #
    # The code is normalised to unsigned first, because it reaches us signed
    # (-1978335189) from Start-Process but the literal 3010 above is positive and
    # would not match a signed equivalent.
    #
    # Anything else stays a real failure, so a genuinely broken install is still
    # reported.
    param([long]$Code)
    $c = $Code
    if ($c -lt 0) { $c += 4294967296 }
    if ($c -eq 0) { return $true }
    if ($c -eq 3010 -or $c -eq 1641) { return $true }
    if ((Get-CodeHex $Code) -eq '8A15002B') { return $true }
    return $false
}

function Update-ProcessPath {
    # Refreshes the process PATH from the registry (Machine + User) WITHOUT
    # discarding the live session value. A newly installed tool adds its entry
    # to the registry, not to the already-running cmd.exe/powershell.exe, so
    # the running process must re-read it. But the session value may hold
    # entries (nvm shims, a manually prepended dir) that are not in the registry
    # at all - overwriting PATH wholesale throws those away, which is how a
    # working Node goes missing.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')

    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($chunk in @($machine, $user, $env:Path)) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        foreach ($entry in ($chunk -split ';')) {
            $t = $entry.Trim()
            if ($t -and -not $merged.Contains($t)) { $merged.Add($t) }
        }
    }
    if ($merged.Count -gt 0) { $env:Path = ($merged -join ';') }
}

# -----------------------------------------------------------------------------
# Interactive helpers
# -----------------------------------------------------------------------------
function Test-Interactive {
    try { return [bool](-not [Console]::IsInputRedirected) } catch { return $false }
}

function Confirm {
    param([string]$Question, [string]$Default = 'y')
    if ($AssumeYes) { Info "$Question -> yes (-Yes)"; return $true }
    if (-not (Test-Interactive)) {
        Err "No console available for confirmation: $Question"
        Err "Re-run with -Yes, or pass the relevant switch to run non-interactively."
        return $false
    }
    $hint = if ($Default -eq 'y') { 'y/N' } else { 'Y/n' }
    $reply = Read-Host "    ? $Question [$hint]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $Default }
    return ($reply -match '^(y|yes)$')
}

function Confirm-Typed {
    param([string]$Question, [string]$Expected)
    if ($AssumeYes) { Info "$Question -> confirmed (-Yes)"; return $true }
    if (-not (Test-Interactive)) {
        Err "No console available to confirm: $Question"
        Err "Re-run with -Yes if you accept the consequences."
        return $false
    }
    $reply = Read-Host "    ? $Question`n      Type $Expected to continue"
    return ($reply -ceq $Expected)
}

function Read-Value {
    param([string]$Message, [string]$Default = '')
    if (-not (Test-Interactive)) {
        Die "'$Message' needs an answer: re-run with the matching switch (see -Help)."
    }
    if ($Default) { $reply = Read-Host "    ${Message}: [$Default]" -DefaultValue $Default }
    else          { $reply = Read-Host "    ${Message}:" }
    return $reply.Trim()
}

function Read-Secret {
    param([string]$Message)
    if (-not (Test-Interactive)) {
        Die "'$Message' needs an answer: re-run with -DbPassword (see -Help)."
    }
    $secure = Read-Host "    ${Message}:" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try   { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
function Show-Usage {
    $script:Usage = @'
setup.ps1 - one-command setup for the membership app (backend + frontend)

  Prerequisites: Node.js 18+, npm, PostgreSQL 14+ (running on port 5432).
  If anything is missing the script prints the exact install command for your
  platform and asks before running it. Nothing is installed without consent.
  A missing Node/npm never stops the run: the steps that need it are reported
  as skipped and everything else is done.

  Nothing is asked when the prerequisite is already there. Node, npm and psql
  are probed on PATH and in their well-known install directories (psql ships in
  C:\Program Files\PostgreSQL\<version>\bin, which the installer leaves off
  PATH), and an existing backend/.env is reused as it is. Install prompts and
  configuration prompts appear only for what is genuinely missing.

  Steps, in order:
    1. node --version          (installing Node.js if it is missing)
    2. psql --version          (starting the postgresql-* service if it is
                                stopped; installing PostgreSQL if it is missing)
    3. backend/.env            (prompted for every value only when it is
                                missing, or when -ReconfigureEnv is passed)
    4. create the database named in backend/.env
    5. npm ci in backend
    6. seed the demo data      (DESTRUCTIVE, opt-in via -Seed, asks you to
                                type SEED)
    7. npm ci in frontend
    8. OpenCode CLI            (only with -OpenCode: reports the installed
                                version, or offers to install it)

MODES
  .\setup.ps1                      Set up everything. Starts nothing.
  -Start                           Also start backend + frontend in the background
  -Seed                            Seed demo data (off by default; asks you to
                                   type SEED, then does it)
  -NoSeed                          Skip the seed step (the default, kept for
                                   clarity in scripts)
  -Status                          Report what is currently running
  -Stop                            Stop backend + frontend
  -Logs                            Tail both logs (Ctrl+C to stop)
  -Clean                           Stop and remove node_modules + logs

DATABASE
  Every value below is prompted for in backend/.env when the file does not exist
  yet. Press Enter to keep the default. An existing backend/.env is reused and
  never rewritten: its values are printed (secrets masked) and setup moves on.
  Pass -ReconfigureEnv to be asked again and have the file rewritten.

  -DbName NAME        Database to create/use        (default: jasasane_app)
  -DbUser USER        PostgreSQL user               (default: postgres)
  -DbPassword PASS    PostgreSQL password           (default: prompt, hidden)
  -DbHost HOST        PostgreSQL host               (default: localhost)
  -DbPort PORT        PostgreSQL port               (default: 5432)
  -TrustLocalAuth     Skip the password prompt and the credential check.
                        Use only when pg_hba.conf trusts local connections
                        ('trust' or 'peer'). DB_PASSWORD is left empty.

  The remaining backend/.env keys are prompted for too, with these defaults:
    PORT=5000  DB_NAME=jasasane_app  JWT_SECRET=your_super_secret_key_change_this
    OTP_EXPIRY_MINUTES=5  MAX_LOGIN_ATTEMPTS=3  LOCKOUT_MINUTES=15

  No switch exists for JWT_SECRET and the three tuning keys; edit backend/.env
  to change them. The default JWT_SECRET is a known value - anyone who knows it
  can forge login tokens.

PORTS
  -Port PORT          Backend port                  (default: 5000)
  -FrontendPort PORT  Frontend port                 (default: 3000)
  Note: frontend/src/services/api.js hardcodes http://localhost:5000, so
  changing -Port also requires editing that file.

OTHER
  -OpenCode            Check the OpenCode CLI: print its version when it is
                         installed, or offer to install opencode-ai@latest
                         globally via npm when it is not. Also writes
                         opencode.json if that file does not exist. Nothing is
                         installed without confirmation.
  -ReconfigureEnv    Re-ask every backend/.env value and rewrite the file,
                       even though it already exists
  -Dev                Run the backend with nodemon in the foreground
                        (implies -Start, but the frontend stays stopped)
  -Yes                Assume yes for every prompt (non-interactive use)
  -Help               This message

ENVIRONMENT EQUIVALENTS
  DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, JWT_SECRET

NOTES
  * This script sets up the machine and stops there. It starts nothing unless
    you pass -Start or -Dev.
  * Tables (users, otps, records) are created by the seed script when it runs,
    and otherwise by the backend on its first boot.
  * The seed script DELETES every row in records and otps, and every user whose
    phone is not 09999999999 / 09111111111 / 09222222222. It is opt-in: pass
    -Seed, which asks you to type SEED. A run without it never touches data.
  * OTPs are simulated: they are printed to the backend console and nowhere
    else. They are written to logs/backend.log when run in the background.
'@
    Write-Host $script:Usage
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
function Parse-Args {
    param([string[]]$Rest)

    # Force a real array: a lone argument would otherwise bind as a [string],
    # and .Count on a scalar throws under Set-StrictMode.
    [string[]]$args_ = @()
    if ($null -ne $Rest) { $args_ = @($Rest) }
    $i = 0
    while ($i -lt $args_.Count) {
        $a = $args_[$i]
        # -match is case-insensitive, so -DbName, -dbname and --db-name are all
        # accepted. The -? makes the inner hyphen optional so the same switch
        # works in both the PowerShell (-DbName) and POSIX (--db-name) styles.
        switch -Regex ($a) {
            '^-{1,2}(h|help|\?)$'        { Show-Usage; exit 0 }
            '^-{1,2}(y|yes)$'            { $script:AssumeYes = $true }
            '^-{1,2}no-?seed$'            { $script:DoSeed    = $false }
            '^-{1,2}seed$'               { $script:DoSeed    = $true }
            '^-{1,2}start$'              { $script:DoStart   = $true }
            '^-{1,2}dev$'                { $script:RunDev    = $true; $script:DoStart = $true }
            '^-{1,2}trust-?local-?auth$'  { $script:TrustLocalAuth = $true }
            '^-{1,2}re-?configure-?env$'  { $script:ReconfigureEnv = $true }
            '^-{1,2}open-?code$'          { $script:OpenCode     = $true }
            '^-{1,2}status$'             { $script:Mode      = 'status' }
            '^-{1,2}stop$'               { $script:Mode      = 'stop' }
            '^-{1,2}logs$'               { $script:Mode      = 'logs' }
            '^-{1,2}clean$'              { $script:Mode      = 'clean' }
            '^-{1,2}db-?name(=.*)?$'     { $script:DbName     = Resolve-Value $a $args_ ([ref]$i) 'DbName' }
            '^-{1,2}db-?user(=.*)?$'     { $script:DbUser     = Resolve-Value $a $args_ ([ref]$i) 'DbUser' }
            '^-{1,2}db-?password(=.*)?$' { $script:DbPassword = Resolve-Value $a $args_ ([ref]$i) 'DbPassword' }
            '^-{1,2}db-?host(=.*)?$'     { $script:DbHost     = Resolve-Value $a $args_ ([ref]$i) 'DbHost'; $script:DbHostGiven = $true }
            '^-{1,2}db-?port(=.*)?$'     { $script:DbPort     = Resolve-Value $a $args_ ([ref]$i) 'DbPort'; $script:DbPortGiven = $true }
            '^-{1,2}port(=.*)?$'         { $script:ApiPort    = Resolve-Value $a $args_ ([ref]$i) 'Port'; $script:PortGiven = $true }
            '^-{1,2}frontend-?port(=.*)?$' { $script:FrontendPort = Resolve-Value $a $args_ ([ref]$i) 'FrontendPort' }
            default { Die "Unknown option: $a  (try -Help)" }
        }
        $i++
    }

    if (-not $DbName) { $script:DbName = 'jasasane_app' }

    foreach ($pair in @(@($ApiPort,'-Port'), @($FrontendPort,'-FrontendPort'), @($DbPort,'-DbPort'))) {
        if ($pair[0] -notmatch '^\d+$') { Die "$($pair[1]) must be a number" }
    }
}

function Resolve-Value {
    # Supports both -Flag value and -Flag=value. Consumes the value so the
    # caller's index loop does not mistake it for the next option.
    param([string]$Arg, [string[]]$All, [ref]$Index, [string]$Name)
    if ($Arg -match '=') { return ($Arg -split '=', 2)[1] }
    $next = $Index.Value + 1
    if ($next -ge $All.Count) { Die "Missing value for -$Name" }
    $Index.Value = $next
    return $All[$next]
}

# -----------------------------------------------------------------------------
# Platform install hints
# -----------------------------------------------------------------------------
function Get-InstallSpec {
    # -> the installer for one dependency as a hashtable, never a bare string:
    #      Exe     = executable to launch
    #      Args    = argv, already split (Start-Process needs this; splitting a
    #                command string would break on quoted args and spaces)
    #      Display = the whole thing as one line, for "Install command:"
    #      Url     = the manual download page, always present, so any message
    #                that needs a link can show a bare URL and nothing else
    #      Manual  = $true when there is no package manager at all, so the only
    #                option is a web page. Must never be executed.
    #
    # The agreement flags are deliberate. Without them winget can stop on an
    # interactive source/package agreement prompt, which reads as a hang - the
    # exact "no progress" symptom this function exists to remove.
    #
    # Note the progress reality: winget's percentage covers the DOWNLOAD only.
    # The MSI install that follows reports an indeterminate spinner, and its
    # InstallationProgress is 0 via the COM API. So a bar would sit at 100%
    # through the slow part. Letting winget draw its own renderer is more honest
    # than faking a percentage we do not have.
    param([ValidateSet('Node','Postgres')][string]$Kind)

    if ($Kind -eq 'Node') {
        $id = 'OpenJS.NodeJS.LTS'; $chocoId = 'nodejs-lts'; $url = 'https://nodejs.org/en/download'
    } else {
        $id = 'PostgreSQL.PostgreSQL.16'; $chocoId = 'postgresql16'; $url = 'https://www.postgresql.org/download/windows/'
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        # Named $argv, not $args: $args is an automatic variable, and shadowing
        # it is the kind of thing that behaves differently on PowerShell 5.1.
        $argv = @('install', '-e', '--id', $id,
                  '--accept-package-agreements', '--accept-source-agreements')
        return @{ Exe = 'winget'; Args = $argv; Display = "winget $($argv -join ' ')"; Manual = $false; Url = $url }
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $argv = @('install', $chocoId, '-y')
        return @{ Exe = 'choco'; Args = $argv; Display = "choco $($argv -join ' ')"; Manual = $false; Url = $url }
    }
    return @{ Exe = $null; Args = @(); Display = $url; Manual = $true; Url = $url }
}

function Node-InstallHint {
    # Kept as a one-liner so every existing "Fix: $(Node-InstallHint)" message and
    # the --help text stay accurate whichever package manager is present.
    (Get-InstallSpec -Kind Node).Display
}

function Pg-InstallHint {
    (Get-InstallSpec -Kind Postgres).Display
}

function Pg-StartHint {
    if (Get-Command net -ErrorAction SilentlyContinue) {
        'net start postgresql-x64-16    # from an Administrator prompt'
    } else {
        'start the PostgreSQL 16 Windows service'
    }
}

function Invoke-Installer {
    # Invoke-Installer -Exe <name> -Argv <argv>  -> [int] exit code
    #
    # Start-Process with -NoNewWindow is what makes progress output appear at all.
    # PowerShell captures a native command's stdout through a PIPE in order to
    # build pipeline objects, and winget builds its progress bar only when stdout
    # is a real console:
    #
    #     if (GetConsoleWidth().has_value())   // AppInstallerCLICore/ExecutionReporter.cpp
    #
    # So the old `Invoke-Expression $Hint | Out-Null` guaranteed no progress:
    #   winget >= 1.29  -> progress suppressed entirely
    #   winget <  1.29  -> bar spam with mojibake (winget-cli#2582)
    #
    # -NoNewWindow inherits the parent console handle, so the bar renders.
    # -PassThru is required to read ExitCode; a bare native call does not throw
    # on failure, which is why the old code reported success even when the
    # installer had failed.
    param([string]$Exe, [string[]]$Argv = @())

    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
        Err "$Exe was not found on PATH."
        return 127
    }
    try {
        $proc = Start-Process -FilePath $Exe -ArgumentList $Argv -NoNewWindow -Wait -PassThru -ErrorAction Stop
        # Some exit codes are only populated after the handle is refreshed.
        try { $proc.Refresh() } catch { }
        return [int]$proc.ExitCode
    } catch {
        Err "Could not start '$Exe': $($_.Exception.Message)"
        return 127
    }
}

function Offer-Install {
    # Offer-Install -Label <name> -Kind Node|Postgres  -> [bool]
    #
    # Takes a -Kind rather than a command string, so this function can tell the
    # difference between "a command we can run" and "a URL a human must open".
    param([string]$Label, [ValidateSet('Node','Postgres')][string]$Kind)

    $spec = Get-InstallSpec -Kind $Kind
    Warn "$Label is required."

    if ($spec.Manual) {
        # There is no package manager on this machine, so there is nothing to
        # execute. The old code passed this URL to Invoke-Expression, which threw
        # and reported "Install command failed: https://..." - technically honest
        # but useless. Say what actually has to happen instead.
        Info "No winget or choco found, so this cannot be installed automatically."
        Info "Download and install it from: $($spec.Url)"
        return $false
    }

    Info "Install command: $($spec.Display)"
    if (-not (Confirm 'Install it now?' 'n')) { return $false }

    Info 'Running it now. winget shows its own progress bar; the MSI install'
    Info 'phase after the download reports a spinner, not a percentage.'
    Info 'A UAC prompt may appear for a machine-wide install - that is expected.'

    $code = Invoke-Installer -Exe $spec.Exe -Argv $spec.Args
    if (-not (Test-InstallerSucceeded $code)) {
        Err "Install failed (exit code $code / 0x$(Get-CodeHex $code)): $($spec.Display)"
        return $false
    }

    if ($code -eq 3010 -or $code -eq 1641) {
        Note "$Label installed; Windows wants a reboot (exit code $code). Continuing."
    } elseif ((Get-CodeHex $code) -eq '8A15002B') {
        Note "$Label is already installed - the installer had nothing to do (0x8A15002B)."
    } else {
        Ok "$Label installed."
    }

    # Refresh PATH so the newly installed tool is visible to this process.
    Update-ProcessPath
    return $true
}

# -----------------------------------------------------------------------------
# Phase 1 - prerequisites
# -----------------------------------------------------------------------------
function Get-NodeMajor {
    # -> the installed major version as an [int], or a negative sentinel:
    #      -1 = node is not on PATH, -2 = node is there but `node -p` said
    #      something unparseable. Both are negative so `$major -ge $MinNodeMajor`
    #      stays false for them.
    # TryParse instead of a bare [int] cast so an unexpected `node -p` result
    # cannot become a terminating error under Set-StrictMode /
    # $ErrorActionPreference = 'Stop'.
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return -1 }
    # The expression MUST stay free of double quotes. Windows PowerShell 5.1 passes
    # native arguments as a raw command line without escaping quotes, so
    # `split(".")` reaches node as `split(.)` - a SyntaxError on stderr, which
    # Invoke-NativeQuiet discards, leaving no output and the -2 sentinel above.
    # That made setup claim Node was unusable and prompt to install it on a
    # perfectly healthy machine. A regex literal has no quotes for the argv
    # parser to consume. PowerShell 7.3+ escapes this correctly by default; 5.1
    # does not, and setup.bat falls back to 5.1 whenever pwsh is absent.
    $out = @((Invoke-NativeQuiet -Exe node -Rest @(
        '-p', 'process.versions.node.split(/\./)[0]'
    )).Output)
    # Only the FIRST line is inspected. A wrapper that prints a banner before the
    # version would otherwise make the whole capture an array and .Trim() would
    # throw under Set-StrictMode. No output at all is the same unreadable case.
    $raw = if ($out.Count -gt 0) { $out[0] } else { '' }
    $major = 0
    if ([int]::TryParse(("$raw").Trim(), [ref]$major)) { return $major }
    return -2
}

function Get-NodeProblem {
    # -> why Node is unusable right now, or '' when it is usable. Shared by the
    #    pre-install warning and the post-install re-check so the two cannot
    #    drift apart.
    param([int]$Major)
    if ($Major -ge $MinNodeMajor) { return '' }
    if ($Major -eq -1) { return 'Node.js is not on PATH.' }
    if ($Major -eq -2) {
        return "Node.js is on PATH but 'node -p' did not report a version (a wrapper script or IDE shim may be shadowing it)."
    }
    $ver = Get-NodeVersionText
    return "Node.js $ver is too old (need >= $MinNodeMajor)."
}

function Join-PathOrNull {
    # Join-Path, but returns $null instead of throwing when the parent is unset.
    # Every one of these variables can legitimately be missing on Windows: a
    # service account or SYSTEM context has no LOCALAPPDATA or APPDATA, and a
    # trimmed install has no ProgramData. A terminating "Cannot bind argument to
    # parameter 'Path'" here would abort the whole run over an optional probe -
    # exactly the failure mode this script must not have.
    param([string]$Base, [string]$Leaf)
    if ([string]::IsNullOrWhiteSpace($Base)) { return $null }
    try { return (Join-Path $Base $Leaf) } catch { return $null }
}

function Get-NodeCandidateDirs {
    # Well-known Node install directories, in the order they are probed. Every
    # entry is checked for node.exe before it is added, so a stale or partial
    # directory cannot put a broken path on PATH.
    $candidates = @(
        (Join-PathOrNull $env:ProgramFiles 'nodejs')
        (Join-PathOrNull ${env:ProgramFiles(x86)} 'nodejs')
        (Join-PathOrNull $env:LOCALAPPDATA 'Programs\nodejs')
        (Join-PathOrNull $env:APPDATA 'npm')
        (Join-PathOrNull $env:ProgramData 'nvm')
        (Join-PathOrNull $env:APPDATA 'nvm')
    )

    $found = @()
    foreach ($d in $candidates) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (Test-Path (Join-Path $d 'node.exe')) { $found += $d }
    }
    # `,$found` forces an array through the pipeline. Without it a single hit is
    # unrolled to a bare [string] by PowerShell's output enumeration, and the
    # caller's .Count then throws under Set-StrictMode 2.0.
    return ,$found
}

function Resolve-NodeOnPath {
    # -> [bool] $true when `node` is callable in THIS process afterwards.
    #
    # Re-reads PATH from the registry first (an installer wrote the new entry
    # there, not into this process), then falls back to the well-known install
    # directories. The fallback is what fixes a Node that is installed and
    # working but invisible to the running terminal - the common case after an
    # install, or with an nvm/shim setup whose PATH entry lives only in the
    # session that started it.
    Update-ProcessPath
    if (Get-Command node -ErrorAction SilentlyContinue) { return $true }

    foreach ($dir in (Get-NodeCandidateDirs)) {
        $env:Path = "$dir;$env:Path"
        if (Get-Command node -ErrorAction SilentlyContinue) {
            Info "Found Node.js in $dir (added to this session's PATH)."
            return $true
        }
    }
    return $false
}

function Get-NpmCandidateDirs {
    # Well-known npm directories, probed only for npm.cmd. npm ships inside the
    # Node install, which Resolve-NodeOnPath has normally already put on PATH;
    # the cases this covers are a global prefix (%APPDATA%\npm) that is not on
    # PATH, and a Node found in a directory that holds node.exe but no npm.cmd.
    $candidates = @((Join-PathOrNull $env:APPDATA 'npm'))

    # Get-Command can return node.exe AND node.cmd, and a function or alias
    # named node has no file path at all. -First 1 keeps $nodeCmd a single
    # object, and the Source test keeps Split-Path away from an empty argument -
    # either would be a binding error, and $ErrorActionPreference = 'Stop' would
    # turn a cosmetic probe into a crash.
    $nodeCmd = @(Get-Command node -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($nodeCmd -and $nodeCmd.Source -and ($nodeCmd.Source -match '[\\/]')) {
        try   { $nodeDir = Split-Path -Path $nodeCmd.Source -Parent }
        catch { $nodeDir = '' }
        if ($nodeDir) { $candidates += $nodeDir }
    }

    $found = @()
    foreach ($d in $candidates) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (Test-Path (Join-Path $d 'npm.cmd')) { $found += $d }
    }
    return ,$found
}

function Resolve-NpmOnPath {
    # -> [bool] $true when `npm` is callable in THIS process afterwards.
    #
    # Only a fallback: npm is checked with Get-Command first, because a broken
    # PATH entry must not be replaced silently by a different npm.
    if (Get-Command npm -ErrorAction SilentlyContinue) { return $true }
    foreach ($dir in (Get-NpmCandidateDirs)) {
        $env:Path = "$dir;$env:Path"
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Info "Found npm in $dir (added to this session's PATH)."
            return $true
        }
    }
    return $false
}

function Get-OpenCodeCandidateDirs {
    # Directories a global `npm install -g opencode-ai` can drop the `opencode`
    # shim into, probed for opencode.cmd.
    #
    # The global npm prefix is the whole reason this function exists. On Windows
    # the Node installer does NOT put the npm global bin directory on PATH, so a
    # perfectly successful `npm install --global opencode-ai` can leave the CLI
    # installed and still not callable. The same class of problem as psql in
    # C:\Program Files\PostgreSQL\<version>\bin.
    $candidates = @((Join-PathOrNull $env:APPDATA 'npm')
                     (Join-PathOrNull $env:LOCALAPPDATA 'npm')
                     (Join-PathOrNull $env:ProgramFiles 'nodejs'))

    # Reuse the npm probes rather than repeating them: the npm global prefix and
    # the resolved npm.cmd's own directory are both plausible locations.
    $candidates += @(Get-NpmCandidateDirs)

    $found = @()
    foreach ($d in $candidates) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (Test-Path (Join-Path $d 'opencode.cmd')) { $found += $d }
    }
    return ,$found
}

function Resolve-OpenCodeOnPath {
    # -> [bool] $true when `opencode` is callable in THIS process afterwards.
    # Never prompts - safe for the -Status mode, which must stay non-interactive.
    if (Get-Command opencode -ErrorAction SilentlyContinue) { return $true }
    foreach ($dir in (Get-OpenCodeCandidateDirs)) {
        $env:Path = "$dir;$env:Path"
        if (Get-Command opencode -ErrorAction SilentlyContinue) {
            Info "Found opencode in $dir (added to this session's PATH)."
            return $true
        }
    }
    return $false
}

function Get-OpenCodeVersion {
    # -> [string] the reported version, or 'unknown' if it cannot be read.
    # First line only, for the same reason as Get-NodeVersionText: a wrapper that
    # prints a banner would make the capture an array.
    if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) { return 'unknown' }
    $out = @((Invoke-NativeQuiet -Exe opencode -Rest @('--version')).Output)
    $raw = if ($out.Count -gt 0) { "$($out[0])".Trim() } else { '' }
    if ($raw) { return $raw }
    return 'unknown'
}

function Write-OpenCodeConfig {
    # Creates opencode.json when it is missing. Never overwrites one that exists:
    # a developer's model and permission choices are theirs, and a setup script has
    # no business replacing them.
    $file = Join-Path $Root 'opencode.json'
    if (Test-Path $file) {
        Info 'opencode.json already exists - leaving it as it is.'
        return
    }

    # A SINGLE-quoted here-string, deliberately. The content contains "$schema"
    # and a literal "*" key: in a double-quoted here-string PowerShell would try
    # to expand $schema to nothing and corrupt the JSON.
    $content = @'
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
'@

    try {
        # LF, no BOM, trailing newline - byte-for-byte the shape of the .json files
        # already in the repo. The here-string drops the final newline itself, so
        # it has to be added back explicitly.
        [IO.File]::WriteAllText($file, (($content -replace "`r`n", "`n") + "`n"))
    } catch {
        Err "Could not write $(Resolve-Relative $file): $($_.Exception.Message)"
        return
    }
    Ok 'Wrote opencode.json (model opencode/big-pickle, default agent build).'
    Info 'It is listed in .gitignore, so it stays a local file - it will not be committed.'
}

function Ensure-OpenCode {
    # Installs the OpenCode CLI when it is missing, or just reports the version
    # when it is already there. Opt-in via -OpenCode / --opencode.
    Step 'Checking the OpenCode CLI'

    if (-not $script:NpmReady) {
        Warn 'Skipping the OpenCode CLI - npm is not available.'
        Add-SkippedStep 'the OpenCode CLI' 'npm was not found'
        return
    }

    [void](Resolve-OpenCodeOnPath)
    if (Get-Command opencode -ErrorAction SilentlyContinue) {
        # Already installed: report and stop. Asking "Install it now?" here would
        # be the exact complaint this feature exists to remove.
        Ok "opencode $(Get-OpenCodeVersion)"
    } else {
        Info 'Install command: npm install --global opencode-ai@latest'
        if (Confirm 'Install it now?' 'n') {
            Info 'Running it now; a global npm install can take a minute.'
            Info 'A UAC prompt may appear - that is expected for a global npm prefix.'
            & npm install --global opencode-ai@latest
            $code = $LASTEXITCODE

            # Verification, not the exit code, is authoritative - same rule as
            # Ensure-Node. The shim lands in the npm global bin directory, which may
            # not be on PATH yet, so refresh and re-probe before believing either.
            Update-ProcessPath
            [void](Resolve-OpenCodeOnPath)

            if (Get-Command opencode -ErrorAction SilentlyContinue) {
                Ok "opencode $(Get-OpenCodeVersion) installed."
            } elseif ($code -ne 0) {
                Err "npm install --global opencode-ai@latest failed (exit code $code / 0x$(Get-CodeHex $code))."
                Info 'A global install under C:\Program Files\nodejs needs an Administrator prompt;'
                Info 'otherwise run this in a terminal where `npm prefix -g` is writable.'
                Add-SkippedStep 'the OpenCode CLI' "npm install failed (exit code $code)"
            } else {
                Err 'npm reported success but `opencode` is still not callable.'
                Info "It was installed into the npm global prefix, which is not on PATH."
                Info 'Add that directory to PATH and open a new terminal, then re-run.'
                Add-SkippedStep 'the OpenCode CLI' 'installed but not on PATH'
            }
        } else {
            # Declining the install must not skip the config: -OpenCode was an
            # explicit request for the OpenCode workspace, and writing a gitignored
            # local file is not the system change the confirmation guarded.
            Info 'Skipped the install. Run it later with: npm install --global opencode-ai@latest'
        }
    }

    Write-OpenCodeConfig
}

function Get-PgCandidateDirs {
    # PostgreSQL installs to <root>\<major>\bin, and its installer deliberately
    # does NOT add that bin directory to PATH. So on a perfectly normal Windows
    # machine `Get-Command psql` fails even though psql.exe is sitting in
    # C:\Program Files\PostgreSQL\16\bin - and without this probe setup would
    # announce that PostgreSQL is missing and offer to install it over the top of
    # a working installation. Highest version first, so 17 wins over 16.
    $roots = @(
        (Join-PathOrNull $env:ProgramFiles 'PostgreSQL')
        (Join-PathOrNull ${env:ProgramFiles(x86)} 'PostgreSQL')
        (Join-PathOrNull (Join-PathOrNull $env:LOCALAPPDATA 'Programs') 'PostgreSQL')
    )

    $found = @()
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        if (-not (Test-Path $root)) { continue }
        # -Directory: PowerShell 3.0+ and 5.1 both accept it. Get-ChildItem
        # cannot throw here - the -ErrorAction silences a denied directory, and
        # every probe below is guarded by Test-Path.
        $versions = @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -match '^\d+$' } |
                      Sort-Object -Property @{ Expression = { [int]$_.Name } } -Descending)
        foreach ($v in $versions) {
            $bin = Join-Path $v.FullName 'bin'
            if (Test-Path (Join-Path $bin 'psql.exe')) { $found += $bin }
        }
    }
    return ,$found
}

function Resolve-PsqlOnPath {
    # -> [bool] $true when `psql` is callable in THIS process afterwards.
    #
    # The PostgreSQL counterpart of Resolve-NodeOnPath, for the same reason: the
    # service is installed, the client is present, and only PATH is stale. Every
    # caller that decides whether PostgreSQL is available must go through here,
    # otherwise the install offer fires on machines that already have it.
    Update-ProcessPath
    if ((Get-Command psql -ErrorAction SilentlyContinue) -or
        (Get-Command pg_isready -ErrorAction SilentlyContinue)) { return $true }

    foreach ($dir in (Get-PgCandidateDirs)) {
        $env:Path = "$dir;$env:Path"
        if (Get-Command psql -ErrorAction SilentlyContinue) {
            Info "Found psql in $dir (added to this session's PATH)."
            return $true
        }
    }
    return $false
}

function Ensure-Node {
    # Establishes whether Node/npm are usable, and NEVER aborts setup.
    #
    # The old version ended in Die, which meant a stale-PATH machine (Node
    # installed, winget answering 0x8A15002B "already installed") stopped the
    # whole run before the .env, the database and the dependencies. Node is a
    # prerequisite for SOME steps, not for all of them, so a missing toolchain
    # now downgrades those steps to "skipped, here's why" and the rest of setup
    # carries on.
    $major = Get-NodeMajor
    $ver   = Get-NodeVersionText

    if ($major -lt $MinNodeMajor) {
        Warn (Get-NodeProblem $major)

        # Best effort: offer the install, but never let the installer's own exit
        # code decide the outcome. Only the verification below is authoritative.
        [void](Offer-Install -Label "Node.js (>= $MinNodeMajor)" -Kind Node)
    }

    if (Resolve-NodeOnPath) {
        $major = Get-NodeMajor
        $ver   = Get-NodeVersionText
        $script:NodeReady = $true

        if ($major -ge $MinNodeMajor) {
            # No upper bound is enforced or warned about. The old ">20" warning
            # was actively misleading: it told users on Node 22/24 (which work
            # fine) to downgrade to Node 18, which has been end-of-life since
            # April 2025. See README "Prerequisites" for the rationale.
            Ok "Node.js $ver  (need >= $MinNodeMajor)"
        } else {
            # Usable, but too old for this project. Proceeding is the caller's
            # decision, not ours - warn clearly and let setup continue.
            Warn "Node.js $ver is below the required $MinNodeMajor. Upgrade it:"
            Info '  winget install OpenJS.NodeJS.LTS    (or nodejs.org/en/download)'
            Info 'Continuing anyway - npm may fail on this version.'
        }
    } else {
        $script:NodeReady = $false
        Err 'Node.js is still not usable after attempting to install it.'
        Info 'Searched PATH (registry + this session) and these directories:'
        foreach ($dir in (Get-NodeCandidateDirs)) { Info "  $dir" }
        Info "Install it with: $(Node-InstallHint)"
        Info 'Continuing. The steps that need npm will be skipped - re-run setup'
        Info 'after Node is installed to complete them.'
    }
}

function Check-Prereqs {
    Step 'Checking prerequisites'

    # --- Node.js -------------------------------------------------------------
    Ensure-Node

    # --- npm -----------------------------------------------------------------
    # npm.cmd ships in the same directory as node.exe, so Resolve-NodeOnPath
    # above normally makes it resolvable too. This stays a warning: without it,
    # `& npm ci` throws CommandNotFoundException and $ErrorActionPreference='Stop'
    # turns that into an opaque crash instead of the message below.
    if ($script:NodeReady) { [void](Resolve-NpmOnPath) }
    $script:NpmReady = $script:NodeReady -and [bool](Get-Command npm -ErrorAction SilentlyContinue)
    if ($script:NpmReady) {
        $npmVer = @((Invoke-NativeQuiet -Exe npm -Rest @('-v')).Output)
        Ok "npm v$($npmVer -join ' ')"
    } else {
        Warn 'npm is not available. It ships with Node.js.'
        Info "Once Node is installed: $(Node-InstallHint)"
        Add-SkippedStep 'npm-dependent steps' 'npm was not found'
    }

    # --- PostgreSQL ----------------------------------------------------------
    # Must run before the test below. psql is routinely installed without its
    # bin directory on PATH, so probing the well-known install locations first
    # is what keeps this branch - and the install offer in it - for machines that
    # really have no PostgreSQL.
    [void](Resolve-PsqlOnPath)

    if (-not (Get-Command psql -ErrorAction SilentlyContinue) -and
        -not (Get-Command pg_isready -ErrorAction SilentlyContinue)) {
        Info 'Searched PATH (registry + this session) and these directories:'
        foreach ($dir in (Get-PgCandidateDirs)) { Info "  $dir" }
        if (-not (Offer-Install -Label "PostgreSQL (>= $MinPgMajor)" -Kind Postgres)) {
            Die "PostgreSQL is required and was not installed."
        }
    }

    if (Get-Command psql -ErrorAction SilentlyContinue) {
        $pgRaw = (psql --version)
        # "psql (PostgreSQL) 18.6 (Ubuntu ...)" - take the number after the
        # first closing paren, not the first parenthesised token.
        $m = [regex]::Match($pgRaw, '\)\s+(\d+)')
        if ($m.Success) {
            $pgMajor = [int]$m.Groups[1].Value
            if ($pgMajor -lt $MinPgMajor) {
                Die "PostgreSQL '$pgRaw' is older than the required $MinPgMajor. Install a newer server."
            }
            Ok "PostgreSQL client $pgRaw  (need >= $MinPgMajor)"
        } else {
            Warn "Could not parse the PostgreSQL version from '$pgRaw'. Continuing."
        }
    } else {
        Ok 'psql not on PATH - Ensure-Database will report how to fix it'
    }

    Wait-ForPostgres
}

function Test-PostgresReady {
    if (Get-Command pg_isready -ErrorAction SilentlyContinue) {
        $r = Invoke-NativeQuiet -Exe pg_isready -Rest @('-h', $DbHost, '-p', $DbPort, '-q')
        return ($r.ExitCode -eq 0)
    }
    # No pg_isready: fall back to a TCP probe via .NET.
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($DbHost, [int]$DbPort, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(2000, $false)
        $client.Close()
        return $ok
    } catch { return $false }
}

function Start-PostgresService {
    # -> [string] the service that was started, or '' if none was.
    #
    # A machine with PostgreSQL installed and the service stopped is not a
    # machine that needs PostgreSQL installed, and it is not a reason to ask the
    # user anything: starting the service is what setup is for. Getting here means
    # the port probe already failed, so a stopped service is the expected cause.
    #
    # pg_isready has to be resolvable for Test-PostgresReady to work, which is
    # what Resolve-PsqlOnPath guarantees by this point - so if there is no
    # pg_isready, the probe came from the TCP fallback and this stays silent.
    if (-not (Get-Command pg_isready -ErrorAction SilentlyContinue)) { return '' }
    if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) { return '' }

    try {
        $services = @(Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue)
    } catch { return '' }
    if ($services.Count -eq 0) { return '' }

    # Name-sorted descending: postgresql-x64-17 sorts above postgresql-x64-16,
    # so the newest installed server is the one that gets started.
    $target = $services | Sort-Object -Property Name -Descending | Select-Object -First 1
    if (-not $target) { return '' }
    if ($target.Status -ne 'Stopped') { return '' }

    Info "The '$($target.Name)' service is stopped - starting it."
    try {
        # Needs Administrator for a service the current user cannot start; the
        # catch turns that into the manual hint below instead of a crash.
        Start-Service -Name $target.Name -ErrorAction Stop
    } catch {
        Warn "Could not start '$($target.Name)': $($_.Exception.Message)"
        return ''
    }
    Ok "Started the '$($target.Name)' service."
    return $target.Name
}

function Wait-ForPostgres {
    # One immediate check before waiting anything: a server that is already up
    # should not cost a second, and a stopped service should be started before
    # the loop rather than after 30s of it.
    if (-not (Test-PostgresReady)) { [void](Start-PostgresService) }

    Info "Waiting for PostgreSQL on ${DbHost}:$DbPort ..."
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-PostgresReady) {
            Ok "PostgreSQL is accepting connections on ${DbHost}:$DbPort"
            return
        }
        Start-Sleep -Seconds 1
    }

    # The service was started (or never existed) and the port is still dead:
    # something outside setup's reach is wrong, so this is the one case that is
    # worth asking about.
    Warn "PostgreSQL is not answering on ${DbHost}:$DbPort after 30s."
    Info "Start it with: $(Pg-StartHint)"
    if (-not (Confirm 'Retry the check now?' 'y')) {
        Die 'Cannot continue without a running PostgreSQL.'
    }
}

# -----------------------------------------------------------------------------
# Phase 2 - backend/.env
# -----------------------------------------------------------------------------
function Read-DbCoordinatesFromEnv {
    # Seeds $DbHost/$DbPort from an existing backend/.env so that the
    # PostgreSQL wait in Check-Prereqs - which runs before Ensure-Env - probes
    # the host and port the app will actually use. A machine whose .env points at
    # port 5433 must not be told "PostgreSQL is not answering on localhost:5432"
    # and be asked to retry. Silent and one-way: an explicit -DbHost / -DbPort
    # still wins, and nothing here prompts.
    $envFile = Join-Path $BackendDir '.env'
    if (-not (Test-Path $envFile)) { return }

    if (-not $script:DbHostGiven) {
        $v = Get-EnvValue $envFile 'DB_HOST'
        if ($v) { $script:DbHost = $v }
    }
    if (-not $script:DbPortGiven) {
        $v = Get-EnvValue $envFile 'DB_PORT'
        if ($v) { $script:DbPort = $v }
    }
}

function Get-EnvValue {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return '' }
    $line = Select-String -Path $File -Pattern "^\s*$([regex]::Escape($Key))\s*=" -ErrorAction SilentlyContinue |
            Select-Object -First 1
    if (-not $line) { return '' }
    $value = ($line.Line -split '=', 2)[1].Trim()
    return $value.Trim('"').Trim("'")
}

function Read-EnvValue {
    param([string]$Key, [string]$Current)
    if ($Current) { return $Current }
    $value = Get-EnvValue (Join-Path $BackendDir '.env') $Key
    if ($value -in @('your_db_user', 'your_db_password')) { return '' }
    return $value
}

function New-JwtSecret {
    $bytes = New-Object byte[] 48
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Every key of backend/.env, with the default used when the user presses Enter.
# The password is the only one with no default - an empty DB_PASSWORD cannot
# work, so it must be typed.
$script:EnvDefaults = [ordered]@{
    'PORT'                = '5000'
    'DB_HOST'             = 'localhost'
    'DB_PORT'             = '5432'
    'DB_NAME'             = 'jasasane_app'
    'DB_USER'             = 'postgres'
    'DB_PASSWORD'         = ''
    'JWT_SECRET'          = 'your_super_secret_key_change_this'
    'OTP_EXPIRY_MINUTES'  = '5'
    'MAX_LOGIN_ATTEMPTS'  = '3'
    'LOCKOUT_MINUTES'     = '15'
}

function Get-EnvLabel {
    param([string]$Key)
    switch ($Key) {
        'PORT'               { return 'PORT - backend API port' }
        'DB_HOST'            { return 'DB_HOST - PostgreSQL host' }
        'DB_PORT'            { return 'DB_PORT - PostgreSQL port' }
        'DB_NAME'            { return 'DB_NAME - database to create' }
        'DB_USER'            { return 'DB_USER - PostgreSQL user' }
        'DB_PASSWORD'        { return 'DB_PASSWORD - password for that user' }
        'JWT_SECRET'         { return 'JWT_SECRET - token signing key' }
        'OTP_EXPIRY_MINUTES' { return 'OTP_EXPIRY_MINUTES - OTP lifetime' }
        'MAX_LOGIN_ATTEMPTS' { return 'MAX_LOGIN_ATTEMPTS - logins before lockout' }
        'LOCKOUT_MINUTES'    { return 'LOCKOUT_MINUTES - lockout duration' }
    }
    return $Key
}

function Write-EnvFile {
    param([string]$File)
    $content = @(
        "PORT=$ApiPort"
        "DB_HOST=$DbHost"
        "DB_PORT=$DbPort"
        "DB_NAME=$DbName"
        "DB_USER=$DbUser"
        "DB_PASSWORD=$DbPassword"
        "JWT_SECRET=$JwtSecret"
        "OTP_EXPIRY_MINUTES=$OtpExpiryMinutes"
        "MAX_LOGIN_ATTEMPTS=$MaxLoginAttempts"
        "LOCKOUT_MINUTES=$LockoutMinutes"
    ) -join "`r`n"
    [IO.File]::WriteAllText($File, $content + "`r`n")
}

function Show-EnvSummary {
    param([string]$File)
    # Prints the values setup is about to use. The password is masked - this
    # goes to a terminal scrollback and often into a shared terminal recording.
    Info 'Resolved configuration:'
    foreach ($key in $script:EnvDefaults.Keys) {
        $value = Get-EnvValue $File $key
        if ($key -eq 'DB_PASSWORD') { $value = if ($value) { '<set>' } else { '<empty>' } }
        if ($key -eq 'JWT_SECRET') { $value = '<set>' }
        if ([string]::IsNullOrWhiteSpace($value)) { $value = '<empty>' }
        Info ("  {0,-19} {1}" -f $key, $value)
    }
    Info "  DB      ${DbUser}@${DbHost}:${DbPort}/${DbName}"
    Info "  Backend  http://localhost:$ApiPort"
}

function Read-EnvField {
    # Read-EnvField -Key <name> -Label <text> [-Current <value>] [-Secret]
    #   -> the value for one .env key.
    #
    # The prompt shows [-Current] as the default, so pressing Enter keeps what
    # setup would otherwise use (an existing .env value, or a switch). With no
    # console (piped/CI) there is nothing to ask, so the current value is used
    # and the fact is stated - a prompt that cannot be answered must not become a
    # stop.
    param(
        [string]$Key,
        [string]$Label,
        [string]$Current = '',
        [switch]$Secret
    )

    $default = if ($Current) { $Current } else { $script:EnvDefaults[$Key] }

    if (-not (Test-Interactive)) {
        Info "$Label = $default  (not prompted: no console)"
        return $default
    }

    if ($Secret) {
        $typed = Read-Secret $Label
        if ($typed) { return $typed }
        if ($Current) { return $Current }
        return ''
    }
    return (Read-Value $Label $default)
}

function Read-EnvSettings {
    # Prompts for every key in backend/.env, in the same order as the file, each
    # showing the value that pressing Enter would keep.
    $envFile = Join-Path $BackendDir '.env'

    if (-not $script:PortGiven) {
        $portNow = Get-EnvValue $envFile 'PORT'
        if (-not $portNow) { $portNow = $script:EnvDefaults['PORT'] }
        $script:ApiPort = Read-EnvField -Key 'PORT' -Label (Get-EnvLabel 'PORT') -Current $portNow
        if ("$ApiPort" -ne '5000') {
            Warn "PORT=$ApiPort, but the frontend hardcodes http://localhost:5000."
            Info 'frontend/src/services/api.js must be edited to match, or no API call will work.'
        }
    }

    $script:DbHost = Read-EnvField -Key 'DB_HOST' -Label (Get-EnvLabel 'DB_HOST') -Current $DbHost
    $script:DbPort = Read-EnvField -Key 'DB_PORT' -Label (Get-EnvLabel 'DB_PORT') -Current $DbPort
    $script:DbName = Read-EnvField -Key 'DB_NAME' -Label (Get-EnvLabel 'DB_NAME') -Current $DbName
    $script:DbUser = Read-EnvField -Key 'DB_USER' -Label (Get-EnvLabel 'DB_USER') -Current $DbUser

    if ($TrustLocalAuth) {
        $script:DbPassword = ''
        Info '-TrustLocalAuth: not asking for a password (PostgreSQL trusts local connections)'
    } else {
        $script:DbPassword = Read-EnvField -Key 'DB_PASSWORD' -Label (Get-EnvLabel 'DB_PASSWORD') -Current $DbPassword -Secret
        if (-not $DbPassword) {
            Warn 'No DB_PASSWORD. Setup will try the connection anyway and report if it is rejected.'
        }
    }

    $script:JwtSecret = Read-EnvField -Key 'JWT_SECRET' -Label (Get-EnvLabel 'JWT_SECRET') -Current $JwtSecret
    if ($JwtSecret -eq 'random') {
        # The literal default is a known value, so offer a way out of it that does
        # not require the user to invent a long string by hand.
        $script:JwtSecret = New-JwtSecret
        Ok 'Generated a fresh 48-byte JWT_SECRET.'
    } elseif ($JwtSecret -eq $script:EnvDefaults['JWT_SECRET']) {
        Warn 'Using the default JWT_SECRET. Anyone who knows it can forge login tokens.'
        Info "Type 'random' at that prompt for a generated one."
        Info 'Change it before anyone else can reach this app.'
    }

    $script:OtpExpiryMinutes = Read-EnvField -Key 'OTP_EXPIRY_MINUTES' -Label (Get-EnvLabel 'OTP_EXPIRY_MINUTES') -Current $OtpExpiryMinutes
    $script:MaxLoginAttempts = Read-EnvField -Key 'MAX_LOGIN_ATTEMPTS' -Label (Get-EnvLabel 'MAX_LOGIN_ATTEMPTS') -Current $MaxLoginAttempts
    $script:LockoutMinutes    = Read-EnvField -Key 'LOCKOUT_MINUTES'    -Label (Get-EnvLabel 'LOCKOUT_MINUTES')    -Current $LockoutMinutes
}

function Ensure-Env {
    Step 'Configuring the backend environment'

    $envFile = Join-Path $BackendDir '.env'
    $example = Join-Path $BackendDir '.env.example'
    $existing = Test-Path $envFile

    # Seed the script-scoped values from the switches, then from the existing
    # file. Anything supplied explicitly always wins over the file.
    $script:DbHost             = Read-EnvValue 'DB_HOST'             $DbHost
    $script:DbPort             = Read-EnvValue 'DB_PORT'             $DbPort
    $script:DbName             = Read-EnvValue 'DB_NAME'             $DbName
    $script:DbUser             = Read-EnvValue 'DB_USER'             $DbUser
    $script:DbPassword         = Read-EnvValue 'DB_PASSWORD'         $DbPassword
    $script:JwtSecret          = Read-EnvValue 'JWT_SECRET'          $JwtSecret
    # No switch exists for the three tuning keys, so they come from the file and
    # fall back to the documented defaults. Read-EnvValue returns $Current
    # unchanged when it is set, so it must be passed '' to consult the file at all.
    $script:OtpExpiryMinutes   = Read-EnvValue 'OTP_EXPIRY_MINUTES'  ''
    if (-not $OtpExpiryMinutes) { $script:OtpExpiryMinutes = $script:EnvDefaults['OTP_EXPIRY_MINUTES'] }
    $script:MaxLoginAttempts   = Read-EnvValue 'MAX_LOGIN_ATTEMPTS'  ''
    if (-not $MaxLoginAttempts) { $script:MaxLoginAttempts = $script:EnvDefaults['MAX_LOGIN_ATTEMPTS'] }
    $script:LockoutMinutes     = Read-EnvValue 'LOCKOUT_MINUTES'     ''
    if (-not $LockoutMinutes) { $script:LockoutMinutes = $script:EnvDefaults['LOCKOUT_MINUTES'] }

    if ($existing) {
        $envPort = Get-EnvValue $envFile 'PORT'
        if ($envPort -and -not $script:PortGiven) {
            $script:ApiPort = $envPort
            Info "Using PORT=$ApiPort from the existing backend/.env"
        }

        Show-EnvSummary $envFile

        # Nothing to ask about. An existing .env is a finished decision - a
        # working DB password in it must not be re-typed on every re-run just to
        # confirm it, and asking makes a plain `setup.bat` block on input even
        # when the machine is fully set up and nothing needs changing. Re-entering
        # is opt-in via -ReconfigureEnv. Matches setup.sh, which never rewrites
        # an existing file.
        if (-not $ReconfigureEnv) {
            Ok 'Reusing backend/.env as it is - pass -ReconfigureEnv to change any value.'
            return
        }

        Warn '-ReconfigureEnv: re-asking every value in backend/.env ...'
        Read-EnvSettings
    } else {
        if (-not (Test-Path $example)) { Die 'backend/.env.example is missing; cannot create backend/.env' }
        Info 'Creating backend/.env - press Enter to accept each default.'
        Read-EnvSettings
    }

    foreach ($pair in @(@($ApiPort,'PORT'),
                        @($OtpExpiryMinutes,'OTP_EXPIRY_MINUTES'),
                        @($MaxLoginAttempts,'MAX_LOGIN_ATTEMPTS'),
                        @($LockoutMinutes,'LOCKOUT_MINUTES'))) {
        if ("$($pair[0])" -notmatch '^\d+$') { Die "$($pair[1]) must be a number, got '$($pair[0])'" }
    }

    Write-EnvFile $envFile
    # Best effort: restrict to the current user. Windows ACLs need icacls.
    try { (Invoke-NativeQuiet -Exe icacls -Rest @($envFile, '/inheritance:r', '/grant:r', "$($env:USERNAME):(R,W)")) | Out-Null } catch { }
    Ok 'Wrote backend/.env (gitignored)'
    Show-EnvSummary $envFile
}

# -----------------------------------------------------------------------------
# Phase 3 - database
# -----------------------------------------------------------------------------
function Invoke-Psql {
    param([string]$Database, [string]$Sql)
    # Without this guard, `& psql` on a machine with no psql on PATH throws a
    # CommandNotFoundException, which $ErrorActionPreference = 'Stop' turns into
    # an unhandled crash instead of the readable error Ensure-Database prints.
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { return $null }
    $prev = $env:PGPASSWORD
    $env:PGPASSWORD = $DbPassword
    try {
        $r = Invoke-NativeQuiet -Exe psql -Rest @(
            '-h', $DbHost,
            '-p', $DbPort,
            '-U', $DbUser,
            '-d', $Database,
            '-v', 'ON_ERROR_STOP=1',
            '-tAc', $Sql
        )
        return $r.Output
    } finally {
        $env:PGPASSWORD = $prev
    }
}

function Assert-PsqlAvailable {
    # Re-probe rather than trusting the Check-Prereqs result: this is the last
    # gate before the script dies, and it must agree with the check that decided
    # whether to offer an install. Cheap - the PATH is already warm by now.
    [void](Resolve-PsqlOnPath)
    if (Get-Command psql -ErrorAction SilentlyContinue) { return }
    Err 'psql is not on PATH, so the database cannot be created automatically.'
    Info 'Add the PostgreSQL bin directory to your PATH (e.g. C:\Program Files\PostgreSQL\16\bin),'
    Info 'or create the database yourself from a terminal that can reach psql:'
    Info "  createdb -U postgres -h $DbHost -p $DbPort $DbName"
    Info 'then re-run this script.'
    Die 'Cannot continue without the psql client.'
}

function Ensure-Database {
    Step 'Preparing the database'

    Assert-PsqlAvailable

    # 1. Verify the credentials with a read-only query. -TrustLocalAuth skips the
    #    check, mirroring setup.sh --trust-local-auth.
    $connected = $TrustLocalAuth
    $reason    = if ($TrustLocalAuth) { '-TrustLocalAuth (no password check)' } else { '' }

    if (-not $connected) {
        if (Invoke-Psql 'postgres' 'SELECT 1;' | Select-Object -First 1) {
            Ok "Authenticated as '$DbUser'"
        } else {
            Err "PostgreSQL rejected the credentials for '$DbUser'."
            Info "Check the password, and that the host is right (${DbHost}:${DbPort})."
            Info 'Windows: the password must be set inside PostgreSQL, not just in the installer.'
            Info "  psql -U postgres -c \"ALTER USER $DbUser WITH PASSWORD '...'\";"
            Info "If pg_hba.conf is set to 'trust' instead, re-run with -TrustLocalAuth."
            if ((Test-Interactive) -and (Confirm 'Re-enter the database password?' 'y')) {
                $script:DbPassword = Read-Secret "PostgreSQL password for '$DbUser'"
                Write-EnvFile (Join-Path $BackendDir '.env')
                if (Invoke-Psql 'postgres' 'SELECT 1;' | Select-Object -First 1) {
                    Ok "Authenticated as '$DbUser'"
                    $connected = $true
                } else {
                    Die "Still failing to authenticate as '$DbUser'."
                }
            } else {
                Die 'Cannot continue without valid database credentials.'
            }
        }
    } else {
        Ok "Not verifying the password: $reason"
    }

    # 2. Create the database if it is missing.
    $exists = @(Invoke-Psql 'postgres' "SELECT 1 FROM pg_database WHERE datname = '$DbName';")
    if ("$($exists[0])".Trim() -eq '1') {
        Ok "Database '$DbName' already exists"
    } else {
        Info "Creating database '$DbName'"
        $prev = $env:PGPASSWORD
        $env:PGPASSWORD = $DbPassword
        try {
            $created = Invoke-NativeQuiet -Exe psql -Rest @(
                '-h', $DbHost,
                '-p', $DbPort,
                '-U', $DbUser,
                '-d', 'postgres',
                '-v', 'ON_ERROR_STOP=1',
                '-tAc', "CREATE DATABASE `"$DbName`";"
            )
            if ($created.ExitCode -eq 0) { Ok "Created database '$DbName'" }
            else {
                Err "CREATE DATABASE '$DbName' failed."
                Info "If the name is not a valid identifier, pass a simpler one: -DbName myapp"
                Info "If the credentials are wrong, re-run with -DbPassword ... (or -TrustLocalAuth"
                Info "if pg_hba.conf trusts local connections)."
                Die "Could not create the database '$DbName'."
            }
        } finally { $env:PGPASSWORD = $prev }
    }

    # 3. Confirm we can open it (catches missing privileges early).
    if (Invoke-Psql $DbName 'SELECT 1;' | Select-Object -First 1) {
        Ok "Database '$DbName' is reachable"
    } else {
        Err "'$DbUser' cannot open database '$DbName'."
        Info "Grant access with: psql -U postgres -c `"GRANT ALL ON DATABASE ""$DbName"" TO ""$DbUser"";`""
        Die 'Database access denied.'
    }

    Info 'Setup creates the database only. The tables (users, otps, records) are'
    Info 'created by the backend the first time you run it (npm run dev / npm start).'
}

# -----------------------------------------------------------------------------
# Phase 4 - dependencies
# -----------------------------------------------------------------------------
function Install-Deps {
    # -> [bool] $true when the dependencies are in place afterwards.
    param([string]$Dir, [string]$Label, [string]$Sentinel)

    if (-not $script:NpmReady) {
        Warn "Skipping the $Label dependencies - npm is not available."
        Add-SkippedStep "$Label dependencies (npm ci)" 'npm was not found'
        return $false
    }

    $sentinelPath = Join-Path $Dir "node_modules\$Sentinel\package.json"
    if (Test-Path $sentinelPath) {
        Ok "$Label dependencies already installed (found $Sentinel)"
        return $true
    }

    Info "Installing $Label dependencies (this can take a few minutes)..."
    Push-Location $Dir
    try {
        if (Test-Path (Join-Path $Dir 'package-lock.json')) {
            & npm ci --no-audit --no-fund
            if ($LASTEXITCODE -eq 0) { Ok "$Label dependencies installed (npm ci)"; return $true }
            Warn "'npm ci' failed. Retrying with 'npm install' ..."
        }
        & npm install --no-audit --no-fund
        if ($LASTEXITCODE -eq 0) { Ok "$Label dependencies installed (npm install)"; return $true }
    } finally {
        Pop-Location
    }

    Err "Installing $Label dependencies failed."
    if ($Label -eq 'backend') {
        Info 'The backend uses bcrypt, a native module. If no prebuilt binary matched'
        Info 'your platform you will need Visual Studio Build Tools:'
        Info '  npm install --global windows-build-tools'
    }
    Add-SkippedStep "$Label dependencies" 'npm install failed'
    return $false
}

function Install-BackendDependencies {
    # [void] - a bare call would emit Install-Deps' [bool] return into the output
    # stream and print "True" in the middle of the run.
    [void](Install-Deps $BackendDir  'backend'  'express')
}

function Install-FrontendDependencies {
    [void](Install-Deps $FrontendDir 'frontend' 'react-scripts')
}

# -----------------------------------------------------------------------------
# Phase 5 - seed (destructive, runs by default, needs typed confirmation)
# -----------------------------------------------------------------------------
function Invoke-Seed {
    # -> [bool] $true when the database was actually seeded.
    if (-not $script:NpmReady) {
        Warn 'Skipping the seed - npm is not available.'
        Add-SkippedStep 'seed data' 'npm was not found'
        return $false
    }
    if (-not (Test-Path (Join-Path $BackendDir 'node_modules\express\package.json'))) {
        Warn 'Skipping the seed - the backend dependencies are not installed yet.'
        Add-SkippedStep 'seed data' 'backend dependencies missing'
        return $false
    }

    Step 'Seeding demo data'
    Warn 'The seed script is DESTRUCTIVE. It will:'
    Info "  * DELETE every row from the 'records' table"
    Info "  * DELETE every row from the 'otps' table"
    Info '  * DELETE every user except 09999999999, 09111111111, 09222222222'
    Info 'It then re-creates 3 users (password: Password@123) and 10 member records.'

    if (-not (Confirm-Typed 'Proceed with seeding?' 'SEED')) {
        Info 'Seed cancelled. Existing data left untouched.'
        return $false
    }

    Push-Location $BackendDir
    try {
        & npm run seed
        if ($LASTEXITCODE -ne 0) {
            Err 'Seeding failed.'
            Add-SkippedStep 'seed data' 'npm run seed exited non-zero'
            return $false
        }
        Ok 'Seed complete.'
        return $true
    } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Port helpers
# -----------------------------------------------------------------------------
function Get-UnixListenerPids {
    param([int]$Port)
    $pids = @()
    if (Get-Command lsof -ErrorAction SilentlyContinue) {
        $out = (Invoke-NativeQuiet -Exe lsof -Rest @('-ti', "tcp:$Port", '-sTCP:LISTEN')).Output
        if ($out) { $pids = @($out | ForEach-Object { [int]$_ }) }
    }
    if ($pids.Count -eq 0 -and (Get-Command ss -ErrorAction SilentlyContinue)) {
        # Select-String operates on each element of .Output, so .Matches stays valid
        # here - this must NOT be collapsed into a single string.
        $out = (Invoke-NativeQuiet -Exe ss -Rest @('-ltnp')).Output | Select-String -Pattern "[:.]$Port\s"
        if ($out) { $pids = @($out | ForEach-Object { ([regex]::Matches($_, 'pid=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }) }) }
    }
    return @($pids | Where-Object { $_ -gt 0 })
}

function Get-NetstatListenerPids {
    param([int]$Port)
    if (-not (Get-Command netstat -ErrorAction SilentlyContinue)) { return @() }
    $line = (Invoke-NativeQuiet -Exe netstat -Rest @('-ano')).Output | Select-String -Pattern "[:.]$Port\s+.*LISTENING\s+(\d+)\s*$"
    if ($line) { return @($line | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }) }
    return @()
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($conns) { return $true }
    } catch { }
    if (@(Get-NetstatListenerPids $Port).Count -gt 0) { return $true }
    if (@(Get-UnixListenerPids  $Port).Count -gt 0) { return $true }
    return $false
}

function Get-PidsOnPort {
    param([int]$Port)
    $pids = @()
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($conns) { $pids = @($conns | Select-Object -ExpandProperty OwningProcess -Unique) }
    } catch { }
    if ($pids.Count -eq 0) { $pids = @(Get-NetstatListenerPids $Port) }
    if ($pids.Count -eq 0) { $pids = @(Get-UnixListenerPids  $Port) }
    return @($pids)
}

function Show-PortOwner {
    param([int]$Port)
    foreach ($p in (Get-PidsOnPort $Port)) {
        $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.ProcessName } else { 'unknown process' }
        Info "  pid $p : $name"
    }
}

function Assert-PortsFree {
    Step 'Checking ports'
    $busy = $false

    if (Test-PortInUse $ApiPort) {
        Err "Port $ApiPort is already in use (needed by the backend)."
        Show-PortOwner $ApiPort
        $busy = $true
    } else { Ok "Port $ApiPort is free" }

    if (Test-PortInUse $FrontendPort) {
        Err "Port $FrontendPort is already in use (needed by the frontend)."
        Info 'This one matters: the React dev server asks interactively whether to'
        Info 'use a different port, which would hang a background start forever.'
        Show-PortOwner $FrontendPort
        $busy = $true
    } else { Ok "Port $FrontendPort is free" }

    if ($busy) { Die 'Free the ports above (or pass -Port / -FrontendPort) and re-run.' }

    if ($ApiPort -ne '5000') {
        Warn "-Port=$ApiPort differs from the default 5000."
        Note 'frontend/src/services/api.js hardcodes http://localhost:5000 - edit it or the UI will not reach the API.'
    }
    if ($FrontendPort -ne '3000') { Info "Frontend will listen on http://localhost:$FrontendPort" }
}

# -----------------------------------------------------------------------------
# Phase 6 - start / stop
# -----------------------------------------------------------------------------
function Get-SavedPid {
    param([string]$File)
    if (-not (Test-Path $File)) { return 0 }
    $raw = (Get-Content $File -Raw -ErrorAction SilentlyContinue)
    $digits = ($raw -replace '[^0-9]', '')
    if ([string]::IsNullOrWhiteSpace($digits)) { return 0 }
    return [int]$digits
}

function Test-PidAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-DescendantPids {
    # npm spawns node as a child, so killing the recorded PID alone leaves the
    # real server running and still holding the port. Walk the tree depth-first.
    param([int]$ParentPid)

    $result = @()
    if ($ParentPid -le 0) { return $result }

    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        try {
            $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ParentPid" -ErrorAction Stop)
            foreach ($c in $children) {
                $cpid = [int]$c.ProcessId
                $result += @(Get-DescendantPids $cpid)
                $result += $cpid
            }
        } catch { }
        return $result
    }

    if (Get-Command ps -ErrorAction SilentlyContinue) {
        # 'pid=,ppid=' must be passed as ONE argument. Written bare in the source it
        # parsed as two ('pid=' and 'ppid=') because a bare comma is PowerShell's
        # array operator, so ps rejected the format string.
        $lines = (Invoke-NativeQuiet -Exe ps -Rest @('-eo', 'pid=,ppid=')).Output
        foreach ($line in $lines) {
            $parts = (($line -replace '\s+', ' ').Trim()) -split ' '
            if ($parts.Count -ge 2) {
                $ppid = 0
                if ([int]::TryParse($parts[1], [ref]$ppid) -and $ppid -eq $ParentPid) {
                    $cpid = 0
                    if ([int]::TryParse($parts[0], [ref]$cpid)) {
                        $result += @(Get-DescendantPids $cpid)
                        $result += $cpid
                    }
                }
            }
        }
    }
    return $result
}

$script:OwnAncestors = @()

function Get-AncestorPids {
    # PIDs come from files on disk and from port lookups, so never trust them
    # blindly: refuse this process and anything that spawned it.
    $result = @()
    $current = $PID
    for ($i = 0; $i -lt 10; $i++) {
        $ppid = 0
        try {
            if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                $me = Get-CimInstance Win32_Process -Filter "ProcessId=$current" -ErrorAction Stop
                if (-not $me) { break }
                $ppid = [int]$me.ParentProcessId
            } else {
                $line = (Invoke-NativeQuiet -Exe ps -Rest @('-eo', 'pid=,ppid=')).Output | Select-String -Pattern "^\s*$current\s+(\d+)\s*$"
                if (-not $line) { break }
                $ppid = [int]$line.Matches[0].Groups[1].Value
            }
        } catch { break }
        if ($ppid -le 0) { break }
        $result += $ppid
        $current = $ppid
    }
    return @($result)
}

function Test-SafeToKill {
    param([int]$ProcessId)
    if ($ProcessId -le 1) { return $false }
    if ($ProcessId -eq $PID) { return $false }
    if (-not $OwnAncestors) { $script:OwnAncestors = @(Get-AncestorPids) }
    return ($OwnAncestors -notcontains $ProcessId)
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    if (-not (Test-SafeToKill $ProcessId)) { return }
    foreach ($child in @(Get-DescendantPids $ProcessId)) {
        if (Test-SafeToKill $child) { Stop-Process -Id $child -Force -ErrorAction SilentlyContinue }
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-One {
    param([string]$Label, [string]$PidFile, [int]$Port)

    $stopped = $false
    $target = Get-SavedPid $PidFile
    if (Test-PidAlive $target) {
        Stop-ProcessTree $target
        $stopped = $true
    }

    # Backstop: sweep whatever still owns the port.
    foreach ($p in (Get-PidsOnPort $Port)) {
        if (Test-SafeToKill $p) { Stop-ProcessTree $p; $stopped = $true }
    }

    # Give them a moment, then confirm the port is really free.
    if ($stopped) {
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Test-PortInUse $Port)) { break }
            Start-Sleep -Milliseconds 500
        }
        if (Test-PortInUse $Port) {
            foreach ($p in (Get-PidsOnPort $Port)) { Stop-ProcessTree $p }
            Start-Sleep -Milliseconds 500
        }
    }

    Remove-Item $PidFile -ErrorAction SilentlyContinue
    if ($stopped) {
        if (Test-PortInUse $Port) { Warn "$Label stopped but port $Port is still held by another process." }
        else { Ok "$Label stopped" }
    } else {
        Info "${Label}: not running"
    }
}

function Stop-Services {
    Step 'Stopping services'
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Stop-One 'Backend'  $BackendPid  $ApiPort
    Stop-One 'Frontend' $FrontendPid $FrontendPort
}

function Test-ApiHealthy {
    param([string]$Uri)
    try {
        $r = Invoke-RestMethod -Uri $Uri -TimeoutSec 4 -ErrorAction Stop
        return ($r.status -eq 'OK')
    } catch { return $false }
}

function Test-HttpOk {
    param([string]$Uri)
    try {
        $null = Invoke-WebRequest -Uri $Uri -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        # A non-2xx response still proves something is serving.
        if ($_.Exception.Response) { return $true }
        return $false
    }
}

function Show-TailOnFailure {
    param([string]$File, [string]$Label, [int]$Lines = 30)
    if (-not (Test-Path $File)) { return }
    Err "Last $Lines lines of $Label`:"
    Get-Content $File -Tail $Lines -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "      | $_" -ForegroundColor DarkGray
    }
}

function Start-Service {
    param(
        [string]$Label, [string]$Dir, [string]$PidFile,
        [string]$OutLog, [hashtable]$EnvVars
    )

    $existing = Get-SavedPid $PidFile
    if (Test-PidAlive $existing) {
        Ok "$Label is already running (pid $existing)"
        return
    }
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    Set-Content -Path $OutLog -Value '' -NoNewline
    # Older versions wrote a separate stderr file; drop any leftover so a stale
    # log cannot suggest the streams are still split.
    Remove-Item (Join-Path $LogDir '*.error.log') -ErrorAction SilentlyContinue

    # Child processes inherit these; save and restore the session's own values.
    $saved = @{}
    foreach ($k in $EnvVars.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $EnvVars[$k])
    }
    try {
        # npm ships as npm.cmd on Windows; resolve it on PATH before launching so a
        # missing toolchain fails here with a clear message rather than inside cmd.
        if (-not (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue) -and
            -not (Get-Command 'npm'     -ErrorAction SilentlyContinue)) {
            Die 'npm was not found on PATH, so the services cannot be started.'
        }
        if (-not $env:ComSpec) {
            Die 'setup.ps1 can only start services on Windows (no cmd.exe found). Run setup.sh on macOS or Linux.'
        }

        # Start-Process refuses to point -RedirectStandardOutput and -RedirectStandardError
        # at the same file, so the two streams must be merged inside the child shell.
        # This is the Windows equivalent of setup.sh's `exec env "$@" >>"$logfile" 2>&1`.
        # -ArgumentList takes a single string on purpose: an array would make PowerShell
        # add its own outer quoting and cmd would treat the whole line as one token.
        # The log path is quoted because the checkout may live under a path with spaces.
        $cmdLine = '/c npm start > "{0}" 2>&1' -f $OutLog
        $proc = Start-Process -FilePath $env:ComSpec `
                              -ArgumentList $cmdLine `
                              -WorkingDirectory $Dir -PassThru -NoNewWindow
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }

    Set-Content -Path $PidFile -Value $proc.Id -NoNewline
    Info ("{0} starting (pid {1}) -> {2}" -f $Label, $proc.Id, (Resolve-Relative $OutLog))
}

function Resolve-Relative {
    param([string]$Path)
    if ($Path.StartsWith($Root)) { return $Path.Substring($Root.Length + 1) }
    return $Path
}

function Start-Services {
    if (-not $script:NpmReady) {
        Warn 'Skipping -Start: npm is not available, so the app cannot be launched.'
        Add-SkippedStep 'start the backend and frontend' 'npm was not found'
        return
    }

    Step 'Starting services'
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    Start-Service 'Backend'  $BackendDir  $BackendPid  $BackendLog  @{ NODE_ENV = 'development' }
    Start-Service 'Frontend' $FrontendDir $FrontendPid $FrontendLog @{ PORT = $FrontendPort; BROWSER = 'none'; CI = 'false' }

    # Readiness: backend first, because the frontend is useless without it.
    $health = "http://localhost:$ApiPort/api/health"
    Info "Waiting for the backend on $health ..."
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-ApiHealthy $health) { Ok 'Backend is healthy'; $ready = $true; break }
        if (-not (Test-PidAlive (Get-SavedPid $BackendPid))) {
            Err 'The backend process exited.'
            Show-TailOnFailure $BackendLog 'backend.log'
            Err 'Common causes: DB_NAME/DB_USER/DB_PASSWORD wrong in backend/.env,'
            Err "PostgreSQL not running, or port $ApiPort taken."
            Stop-Services | Out-Null
            Die 'Backend failed to start.'
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Err 'Backend did not become healthy within 60s.'
        Show-TailOnFailure $BackendLog 'backend.log'
        Stop-Services | Out-Null
        Die 'Backend failed the health check.'
    }

    $front = "http://localhost:$FrontendPort"
    Info "Waiting for the frontend on $front ..."
    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        if (Test-HttpOk $front) { Ok 'Frontend is serving'; $ready = $true; break }
        if (-not (Test-PidAlive (Get-SavedPid $FrontendPid))) {
            Err 'The frontend process exited.'
            Show-TailOnFailure $FrontendLog 'frontend.log'
            Stop-Services | Out-Null
            Die 'Frontend failed to start.'
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Err 'Frontend did not answer within 90s (the first CRA compile is slow).'
        Show-TailOnFailure $FrontendLog 'frontend.log'
        Stop-Services | Out-Null
        Die 'Frontend failed to start.'
    }
}

function Start-BackendForeground {
    if (-not $script:NpmReady) {
        Warn 'Cannot start the backend: npm is not available.'
        Add-SkippedStep 'run the backend in the foreground' 'npm was not found'
        return
    }

    Step 'Starting the backend with nodemon (foreground)'
    Info 'Press Ctrl+C to stop.'
    Push-Location $BackendDir
    try { & npm run dev } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Status / logs / clean
# -----------------------------------------------------------------------------
function Show-Status {
    Step 'Status'

    $p = Get-SavedPid $BackendPid
    if (Test-PidAlive $p) { Ok "Backend  running  pid $p  http://localhost:$ApiPort" }
    else                  { Info 'Backend  stopped' }

    $p = Get-SavedPid $FrontendPid
    if (Test-PidAlive $p) { Ok "Frontend running  pid $p  http://localhost:$FrontendPort" }
    else                  { Info 'Frontend stopped' }

    if (Test-Path (Join-Path $BackendDir '.env')) { Ok 'backend/.env present' }
    else { Info 'backend/.env missing' }

    if (Test-PostgresReady) { Ok "PostgreSQL accepting connections on ${DbHost}:$DbPort" }
    else                    { Info "PostgreSQL not answering on ${DbHost}:$DbPort" }

    if (Test-Path (Join-Path $BackendDir  'node_modules\express\package.json'))       { Ok 'Backend dependencies installed' }
    else { Info 'Backend dependencies not installed' }
    if (Test-Path (Join-Path $FrontendDir 'node_modules\react-scripts\package.json')) { Ok 'Frontend dependencies installed' }
    else { Info 'Frontend dependencies not installed' }

    # Resolve-OpenCodeOnPath and Get-OpenCodeVersion never prompt, so reporting
    # the CLI here keeps -Status non-interactive.
    if (Resolve-OpenCodeOnPath) { Ok "OpenCode CLI $(Get-OpenCodeVersion)" }
    else { Info 'OpenCode CLI not installed (setup.bat --opencode installs it)' }
}

function Show-Logs {
    $existing = @()
    foreach ($f in @($BackendLog, $FrontendLog)) { if (Test-Path $f) { $existing += $f } }
    if ($existing.Count -eq 0) {
        Die "No logs found in $(Resolve-Relative $LogDir). Start the app first."
    }
    Step 'Tailing logs (Ctrl+C to stop)'
    Info "The OTP is printed by the backend: Select-String -Path $(Resolve-Relative $BackendLog) -Pattern 'OTP'"
    # Get-Content -Wait follows every path given, so this tails the backend and
    # the frontend at once, matching setup.sh.
    Get-Content -Path $existing -Tail 20 -Wait
}

function Invoke-Clean {
    Step 'Cleaning'
    Stop-Services
    if (Confirm 'Delete backend\node_modules and frontend\node_modules?' 'n') {
        Remove-Item (Join-Path $BackendDir 'node_modules')  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $FrontendDir 'node_modules') -Recurse -Force -ErrorAction SilentlyContinue
        Ok 'node_modules removed (the next setup run reinstalls them)'
    } else { Info 'Kept node_modules' }

    if (Confirm "Delete $(Resolve-Relative $LogDir) and backend\.env?" 'n') {
        Remove-Item $LogDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $BackendDir '.env') -Force -ErrorAction SilentlyContinue
        Ok 'Logs and backend/.env removed'
    } else { Info 'Kept logs and backend/.env' }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
function Show-Summary {
    $seeded = if ($DoSeed) { 'yes' } else { 'no' }
    $blog   = Resolve-Relative $BackendLog
    $flog   = Resolve-Relative $FrontendLog
    $ldir   = Resolve-Relative $LogDir

    Write-Host ''
    Write-Host '  Membership app is up' -ForegroundColor Green
    Write-Host ''
    Write-Host "    Frontend   http://localhost:$FrontendPort"
    Write-Host "    Backend    http://localhost:$ApiPort   (health: /api/health)"
    Write-Host "    Database   ${DbUser}@${DbHost}:${DbPort}/${DbName}"
    Write-Host "    Seeded     $seeded"
    Write-Host ''
    Write-Host '  Demo logins (after -Seed)' -ForegroundColor White
    Write-Host ''
    Write-Host '    Admin      09999999999  /  Password@123'
    Write-Host '    Regular    09111111111  /  Password@123'
    Write-Host '    Regular    09222222222  /  Password@123'
    Write-Host ''
    Write-Host '  Where to look next' -ForegroundColor White
    Write-Host ''
    Write-Host "    Logs       .\setup.ps1 -Logs     (also: $flog)"
    Write-Host "    OTP        Select-String -Path $blog -Pattern 'OTP' | Select-Object -Last 1"
    Write-Host '               (OTPs are simulated - printed to the backend console, not sent by SMS)'
    Write-Host '    Stop       .\setup.ps1 -Stop'
    Write-Host '    Status     .\setup.ps1 -Status'
    Write-Host ''
}

function Show-SetupSummary {
    $blog = Resolve-Relative $BackendLog

    if ($script:Skipped.Count -gt 0) {
        Write-Host ''
        Write-Host '  SETUP INCOMPLETE' -ForegroundColor Yellow
        Write-Host '  Some steps could not run:' -ForegroundColor Yellow
        foreach ($s in $script:Skipped) {
            Write-Host ("    - {0}  ({1})" -f $s.Step, $s.Reason) -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host '  Fix the cause above, then re-run setup - it resumes where it left'
        Write-Host '  off and re-uses backend/.env as it is.'
        Write-Host ''
    }

    Write-Host ''
    if ($script:Skipped.Count -gt 0) {
        Write-Host '  Setup finished with skipped steps - nothing was started' -ForegroundColor Yellow
    } else {
        Write-Host '  Setup complete - nothing was started' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host "    Database   ${DbUser}@${DbHost}:${DbPort}/${DbName}"
    Write-Host '    Backend    .env written'
    Write-Host "    Frontend   dependencies $(if ($script:NpmReady) { 'installed' } else { 'NOT installed' })"
    Write-Host "    Seeded     $(if ($DoSeed) { 'requested' } else { 'no (-Seed to enable)' })"
    if ($OpenCode) {
        Write-Host "    OpenCode   $(if (Get-Command opencode -ErrorAction SilentlyContinue) { Get-OpenCodeVersion } else { 'NOT installed' })"
    }
    Write-Host ''
    Write-Host '  Run the app' -ForegroundColor White
    Write-Host ''
    Write-Host '    Backend    cd backend; npm run dev'
    Write-Host "               -> http://localhost:$ApiPort"
    Write-Host '    Frontend   cd frontend; npm start'
    Write-Host "               -> http://localhost:$FrontendPort  (in a second terminal)"
    Write-Host ''
    Write-Host '    The tables (users, otps, records) are created by the backend on its'
    Write-Host '    first boot, so they appear the moment you run it.'
    Write-Host ''
    Write-Host '  Other actions' -ForegroundColor White
    Write-Host ''
    Write-Host '    Both at once   .\setup.ps1 -Start'
    Write-Host "    Logs           .\setup.ps1 -Logs"
    Write-Host "    OTP            Select-String -Path $blog -Pattern 'OTP' | Select-Object -Last 1"
    Write-Host '    Stop           .\setup.ps1 -Stop'
    Write-Host '    Status         .\setup.ps1 -Status'
    Write-Host ''
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
function Invoke-Main {
    Parse-Args -Rest $ScriptArgs

    switch ($Mode) {
        'status'  { Show-Status; exit 0 }
        'stop'    { Stop-Services; exit 0 }
        'logs'    { Show-Logs; exit 0 }
        'clean'   { Invoke-Clean; exit 0 }
    }

    if (-not (Test-Path $BackendDir))  { Die 'backend\ not found next to setup.ps1. Run it from inside the repository.' }
    if (-not (Test-Path $FrontendDir)) { Die 'frontend\ not found next to setup.ps1. Run it from inside the repository.' }

    Write-Host '  membership-app setup' -ForegroundColor Green
    Info "Repository root: $Root"

    # Before Check-Prereqs, so the PostgreSQL wait targets the right coordinates.
    Read-DbCoordinatesFromEnv

    Check-Prereqs
    Ensure-Env
    Ensure-Database

    # The order matters and is deliberate: the seed needs the backend
    # dependencies (it requires bcrypt), and it creates its own tables via
    # backend/src/models/init.js, so it does not need the backend running.
    Step 'Installing backend dependencies'
    Install-BackendDependencies

    if ($DoSeed) { [void](Invoke-Seed) }

    Step 'Installing frontend dependencies'
    Install-FrontendDependencies

    # Opt-in only, and last: it needs npm (known by now) and has nothing to do with
    # the app, so it must not sit inside the backend -> seed -> frontend chain.
    if ($OpenCode) { Ensure-OpenCode }

    # Setup is complete at this point. Starting the app is opt-in (-Start / -Dev).
    if (-not $DoStart) {
        Show-SetupSummary
        exit 0
    }

    Assert-PortsFree

    if ($RunDev) { Start-BackendForeground; exit 0 }

    Start-Services
    Show-Summary
}

Invoke-Main
