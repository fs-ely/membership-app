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
$ApiPort      = 5000
$FrontendPort = 3000

$AssumeYes = $false
$DoSeed    = $false
$DoStart   = $false
$RunDev    = $false
$TrustLocalAuth = $false
$Mode      = 'setup'

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

MODES
  .\setup.ps1                      Set up everything. Starts nothing.
  -Start                           Also start backend + frontend in the background
  -Seed                            Also seed demo data (DESTRUCTIVE, confirms)
  -Status                          Report what is currently running
  -Stop                            Stop backend + frontend
  -Logs                            Tail both logs (Ctrl+C to stop)
  -Clean                           Stop and remove node_modules + logs

DATABASE
  -DbName NAME        Database to create/use        (default: jasasane_app)
  -DbUser USER        PostgreSQL user               (default: prompt)
  -DbPassword PASS    PostgreSQL password           (default: prompt, hidden)
  -DbHost HOST        PostgreSQL host               (default: localhost)
  -DbPort PORT        PostgreSQL port               (default: 5432)
  -TrustLocalAuth     Skip the password prompt and the credential check.
                        Use only when pg_hba.conf trusts local connections
                        ('trust' or 'peer'). DB_PASSWORD is left empty.

PORTS
  -Port PORT          Backend port                  (default: 5000)
  -FrontendPort PORT  Frontend port                 (default: 3000)
  Note: frontend/src/services/api.js hardcodes http://localhost:5000, so
  changing -Port also requires editing that file.

OTHER
  -Dev                Run the backend with nodemon in the foreground
                        (implies -Start, but the frontend stays stopped)
  -Yes                Assume yes for every prompt (non-interactive use)
  -Help               This message

ENVIRONMENT EQUIVALENTS
  DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, JWT_SECRET

NOTES
  * This script sets up the machine and stops there. It starts nothing unless
    you pass -Start or -Dev.
  * Tables (users, otps, records) are created automatically by the backend on
    first boot, not by this script. Run the backend once and they appear.
  * The seed script DELETES every row in records and otps, and every user whose
    phone is not 09999999999 / 09111111111 / 09222222222. It never runs unless
    you pass -Seed.
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
            '^-{1,2}seed$'               { $script:DoSeed    = $true }
            '^-{1,2}start$'              { $script:DoStart   = $true }
            '^-{1,2}dev$'                { $script:RunDev    = $true; $script:DoStart = $true }
            '^-{1,2}trust-?local-?auth$'  { $script:TrustLocalAuth = $true }
            '^-{1,2}status$'             { $script:Mode      = 'status' }
            '^-{1,2}stop$'               { $script:Mode      = 'stop' }
            '^-{1,2}logs$'               { $script:Mode      = 'logs' }
            '^-{1,2}clean$'              { $script:Mode      = 'clean' }
            '^-{1,2}db-?name(=.*)?$'     { $script:DbName     = Resolve-Value $a $args_ ([ref]$i) 'DbName' }
            '^-{1,2}db-?user(=.*)?$'     { $script:DbUser     = Resolve-Value $a $args_ ([ref]$i) 'DbUser' }
            '^-{1,2}db-?password(=.*)?$' { $script:DbPassword = Resolve-Value $a $args_ ([ref]$i) 'DbPassword' }
            '^-{1,2}db-?host(=.*)?$'     { $script:DbHost     = Resolve-Value $a $args_ ([ref]$i) 'DbHost' }
            '^-{1,2}db-?port(=.*)?$'     { $script:DbPort     = Resolve-Value $a $args_ ([ref]$i) 'DbPort' }
            '^-{1,2}port(=.*)?$'         { $script:ApiPort    = Resolve-Value $a $args_ ([ref]$i) 'Port' }
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
function Node-InstallHint {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        'winget install -e --id OpenJS.NodeJS.LTS'
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        'choco install nodejs-lts -y'
    } else {
        'https://nodejs.org/en/download  (install the LTS build)'
    }
}

function Pg-InstallHint {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        'winget install -e --id PostgreSQL.PostgreSQL.16'
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        'choco install postgresql16 -y'
    } else {
        'https://www.postgresql.org/download/windows/'
    }
}

function Pg-StartHint {
    if (Get-Command net -ErrorAction SilentlyContinue) {
        'net start postgresql-x64-16    # from an Administrator prompt'
    } else {
        'start the PostgreSQL 16 Windows service'
    }
}

function Offer-Install {
    param([string]$Label, [string]$Hint)
    Warn "$Label is missing."
    Info "Install command: $Hint"
    if (Confirm 'Install it now?' 'n') {
        Info "Running: $Hint"
        try {
            Invoke-Expression $Hint | Out-Null
            Ok "$Label installed."
            # Refresh PATH so the newly installed tool is visible.
            $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
            $user     = [Environment]::GetEnvironmentVariable('Path', 'User')
            $env:Path = "$machine;$user"
            return $true
        } catch {
            Err "Install command failed: $Hint"
            return $false
        }
    }
    return $false
}

# -----------------------------------------------------------------------------
# Phase 1 - prerequisites
# -----------------------------------------------------------------------------
function Check-Prereqs {
    Step 'Checking prerequisites'

    # --- Node.js -------------------------------------------------------------
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $nodeMajor = [int](node -p 'process.versions.node.split(".")[0]')
        $nodeVer   = (node -v)
        if ($nodeMajor -ge $MinNodeMajor) {
            Ok "Node.js $nodeVer  (need >= $MinNodeMajor)"
        } else {
            Die "Node.js $nodeVer is too old. Need >= $MinNodeMajor. Fix: $(Node-InstallHint)"
        }
        if ($nodeMajor -gt 20) {
            Warn "Node $nodeVer is newer than the documented target (v18)."
            Note "If 'npm start' fails to compile the frontend, install Node 18 LTS and re-run."
        }
    } else {
        if (-not (Offer-Install "Node.js (>= $MinNodeMajor)" (Node-InstallHint))) {
            Die "Node.js is required and was not installed."
        }
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Die 'Node.js still not on PATH. Open a new terminal and re-run.' }
    }

    # --- npm -----------------------------------------------------------------
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Die "npm is missing. It ships with Node.js - reinstall Node, or see: $(Node-InstallHint)"
    }
    Ok "npm v$(npm -v)"

    # --- PostgreSQL ----------------------------------------------------------
    if (-not (Get-Command psql -ErrorAction SilentlyContinue) -and
        -not (Get-Command pg_isready -ErrorAction SilentlyContinue)) {
        if (-not (Offer-Install "PostgreSQL (>= $MinPgMajor)" (Pg-InstallHint))) {
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
        pg_isready -h $DbHost -p $DbPort -q 2>$null
        return ($LASTEXITCODE -eq 0)
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

function Wait-ForPostgres {
    Info "Waiting for PostgreSQL on ${DbHost}:$DbPort ..."
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-PostgresReady) {
            Ok "PostgreSQL is accepting connections on ${DbHost}:$DbPort"
            return
        }
        Start-Sleep -Seconds 1
    }
    Warn "PostgreSQL is not answering on ${DbHost}:$DbPort after 30s."
    Info "Start it with: $(Pg-StartHint)"
    if (-not (Confirm 'Retry the check now?' 'y')) {
        Die 'Cannot continue without a running PostgreSQL.'
    }
}

# -----------------------------------------------------------------------------
# Phase 2 - backend/.env
# -----------------------------------------------------------------------------
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
        'OTP_EXPIRY_MINUTES=5'
        'MAX_LOGIN_ATTEMPTS=3'
        'LOCKOUT_MINUTES=15'
    ) -join "`r`n"
    [IO.File]::WriteAllText($File, $content + "`r`n")
}

function Ensure-Env {
    Step 'Configuring the backend environment'

    $envFile = Join-Path $BackendDir '.env'
    $example = Join-Path $BackendDir '.env.example'
    $existing = Test-Path $envFile

    if ($existing) {
        Ok 'backend/.env already exists - reusing it (it is never overwritten)'
    } else {
        if (-not (Test-Path $example)) { Die 'backend/.env.example is missing; cannot create backend/.env' }
        Info 'Creating backend/.env from backend/.env.example'
    }

    $script:DbName     = Read-EnvValue 'DB_NAME'     $DbName
    $script:DbUser     = Read-EnvValue 'DB_USER'     $DbUser
    $script:DbPassword = Read-EnvValue 'DB_PASSWORD' $DbPassword
    $script:DbHost     = Read-EnvValue 'DB_HOST'     $DbHost
    $script:DbPort     = Read-EnvValue 'DB_PORT'     $DbPort
    $script:JwtSecret  = Read-EnvValue 'JWT_SECRET'  $JwtSecret

    if ($existing) {
        $envPort = Get-EnvValue $envFile 'PORT'
        if ($envPort -and $envPort -ne $ApiPort) {
            $script:ApiPort = $envPort
            Info "Using PORT=$ApiPort from the existing backend/.env"
        }
    }

    if (-not $DbName) { $script:DbName = 'jasasane_app' }
    if (-not $DbUser) { $script:DbUser = Read-Value 'PostgreSQL user' 'postgres' }
    if ($TrustLocalAuth) {
        $script:DbPassword = ''
        Info '-TrustLocalAuth: not asking for a password (PostgreSQL trusts local connections)'
    } elseif (-not $DbPassword) {
        $script:DbPassword = Read-Secret "PostgreSQL password for '$DbUser'"
        if (-not $DbPassword) {
            Die "An empty password was supplied. Check the password for '$DbUser' and try again."
        }
    }
    if (-not $JwtSecret) {
        $script:JwtSecret = New-JwtSecret
        Info 'Generated a fresh 48-byte JWT_SECRET'
    }

    if ($existing) {
        Info 'Resolved configuration:'
        Info "  DB      ${DbUser}@${DbHost}:${DbPort}/${DbName}"
        Info "  Backend  http://localhost:$ApiPort"
        return
    }

    Write-EnvFile $envFile
    # Best effort: restrict to the current user. Windows ACLs need icacls.
    try { icacls $envFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>$null | Out-Null } catch { }
    Ok 'Wrote backend/.env (gitignored)'
    Info "  DB      ${DbUser}@${DbHost}:${DbPort}/${DbName}"
    Info "  Backend  http://localhost:$ApiPort"
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
        $out = & psql -h $DbHost -p $DbPort -U $DbUser -d $Database `
                      -v ON_ERROR_STOP=1 -tAc $Sql 2>$null
        return $out
    } finally {
        $env:PGPASSWORD = $prev
    }
}

function Assert-PsqlAvailable {
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
    $exists = Invoke-Psql 'postgres' "SELECT 1 FROM pg_database WHERE datname = '$DbName';"
    if ("$exists".Trim() -eq '1') {
        Ok "Database '$DbName' already exists"
    } else {
        Info "Creating database '$DbName'"
        $prev = $env:PGPASSWORD
        $env:PGPASSWORD = $DbPassword
        try {
            & psql -h $DbHost -p $DbPort -U $DbUser -d postgres -v ON_ERROR_STOP=1 `
                   -tAc "CREATE DATABASE `"$DbName`";" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "Created database '$DbName'" }
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
    param([string]$Dir, [string]$Label, [string]$Sentinel)

    $sentinelPath = Join-Path $Dir "node_modules\$Sentinel\package.json"
    if (Test-Path $sentinelPath) {
        Ok "$Label dependencies already installed (found $Sentinel)"
        return
    }

    Info "Installing $Label dependencies (this can take a few minutes)..."
    Push-Location $Dir
    try {
        if (Test-Path (Join-Path $Dir 'package-lock.json')) {
            & npm ci --no-audit --no-fund
            if ($LASTEXITCODE -eq 0) { Ok "$Label dependencies installed (npm ci)"; return }
            Warn "'npm ci' failed. Retrying with 'npm install' ..."
        }
        & npm install --no-audit --no-fund
        if ($LASTEXITCODE -eq 0) { Ok "$Label dependencies installed (npm install)"; return }
    } finally {
        Pop-Location
    }

    Err "Installing $Label dependencies failed."
    if ($Label -eq 'backend') {
        Info 'The backend uses bcrypt, a native module. If no prebuilt binary matched'
        Info 'your platform you will need Visual Studio Build Tools:'
        Info '  npm install --global windows-build-tools'
    }
    Die "Cannot continue without $Label dependencies."
}

function Install-Dependencies {
    Step 'Installing dependencies'
    Install-Deps $BackendDir  'backend'  'express'
    Install-Deps $FrontendDir 'frontend' 'react-scripts'
}

# -----------------------------------------------------------------------------
# Phase 5 - seed (opt-in, destructive)
# -----------------------------------------------------------------------------
function Invoke-Seed {
    Step 'Seeding demo data'
    Warn 'The seed script is DESTRUCTIVE. It will:'
    Info "  * DELETE every row from the 'records' table"
    Info "  * DELETE every row from the 'otps' table"
    Info '  * DELETE every user except 09999999999, 09111111111, 09222222222'
    Info 'It then re-creates 3 users (password: Password@123) and 10 member records.'

    if (-not (Confirm-Typed 'Proceed with seeding?' 'SEED')) {
        Info 'Seed cancelled. Existing data left untouched.'
        return
    }

    Push-Location $BackendDir
    try {
        & npm run seed
        if ($LASTEXITCODE -ne 0) { Die 'Seeding failed.' }
        Ok 'Seed complete.'
    } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Port helpers
# -----------------------------------------------------------------------------
function Get-UnixListenerPids {
    param([int]$Port)
    $pids = @()
    if (Get-Command lsof -ErrorAction SilentlyContinue) {
        $out = & lsof -ti "tcp:$Port" -sTCP:LISTEN 2>$null
        if ($out) { $pids = @($out | ForEach-Object { [int]$_ }) }
    }
    if ($pids.Count -eq 0 -and (Get-Command ss -ErrorAction SilentlyContinue)) {
        $out = & ss -ltnp 2>$null | Select-String -Pattern "[:.]$Port\s"
        if ($out) { $pids = @($out | ForEach-Object { ([regex]::Matches($_, 'pid=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }) }) }
    }
    return @($pids | Where-Object { $_ -gt 0 })
}

function Get-NetstatListenerPids {
    param([int]$Port)
    if (-not (Get-Command netstat -ErrorAction SilentlyContinue)) { return @() }
    $line = & netstat -ano 2>$null | Select-String -Pattern "[:.]$Port\s+.*LISTENING\s+(\d+)\s*$"
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
        $lines = & ps -eo pid=,ppid= 2>$null
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
                $line = & ps -eo pid=,ppid= 2>$null | Select-String -Pattern "^\s*$current\s+(\d+)\s*$"
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
    $seeded = if ($DoSeed) { 'yes' } else { 'no' }
    $blog   = Resolve-Relative $BackendLog

    Write-Host ''
    Write-Host '  Setup complete - nothing was started' -ForegroundColor Green
    Write-Host ''
    Write-Host "    Database   ${DbUser}@${DbHost}:${DbPort}/${DbName}"
    Write-Host '    Backend    .env written, dependencies installed'
    Write-Host '    Frontend   dependencies installed'
    Write-Host "    Seeded     $seeded"
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

    Check-Prereqs
    Ensure-Env
    Ensure-Database
    Install-Dependencies

    if ($DoSeed) { Invoke-Seed }

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
