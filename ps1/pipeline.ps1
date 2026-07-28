<#
=====================================================================
run_pipeline.ps1

Runs the full ETL + data-quality pipeline in order:
  1. incremental.py           - pulls/loads new source rows
  2. model/09_pop_dims.sql    - populate dimension tables (idempotent)
  3. model/10_pop_fact.sql    - populate fact table (idempotent)
  4. data_quality_checks.py   - automated DQ checks, exits 1 on failure

$ErrorActionPreference = "Stop" + explicit exit-code checks after every
psql / python call means the script stops immediately at the first
failing step, so a broken load never silently proceeds into the DQ
checks against bad/partial data.

Usage:
  .\run_pipeline.ps1

Config: override any of these via environment variables before running,
e.g.:
  $env:PGHOST="localhost"; $env:PGDATABASE="uber"; $env:PGUSER="postgres"; .\run_pipeline.ps1
=====================================================================
#>

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ScriptsDir  = if ($env:SCRIPTS_DIR) { $env:SCRIPTS_DIR } else { Join-Path $ProjectRoot "scripts" }
$ModelDir    = if ($env:MODEL_DIR)   { $env:MODEL_DIR }   else { Join-Path $ProjectRoot "model" }

# Point this at your venv's python if "python" on PATH isn't the right one,
# e.g. $env:PYTHON = "C:\UBER\.venv\Scripts\python.exe"
$Python = if ($env:PYTHON) { $env:PYTHON } else { "python" }

# Resolve psql: use $env:PSQL if set, else whatever's on PATH, else search
# common Windows install locations (EDB installer, Scoop, Chocolatey).
if ($env:PSQL) {
    $Psql = $env:PSQL
} elseif (Get-Command "psql" -ErrorAction SilentlyContinue) {
    $Psql = "psql"
} else {
    $PsqlSearchPaths = @(
        "C:\Program Files\PostgreSQL\*\bin\psql.exe",
        "C:\Program Files (x86)\PostgreSQL\*\bin\psql.exe",
        "$env:USERPROFILE\scoop\apps\postgresql\current\bin\psql.exe",
        "C:\ProgramData\chocolatey\bin\psql.exe"
    )
    $PsqlFound = Get-ChildItem -Path $PsqlSearchPaths -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($PsqlFound) {
        $Psql = $PsqlFound.FullName
        Write-Host "Found psql at $Psql"
    } else {
        throw "psql.exe not found on PATH or in common install locations. Set `$env:PSQL to its full path, e.g. `$env:PSQL='C:\Program Files\PostgreSQL\16\bin\psql.exe'"
    }
}

# --- DB connection ---
# Loads C:\UBER\_env (POSTGRES_HOST / POSTGRES_PORT / POSTGRES_DATABASE /
# POSTGRES_USERNAME / POSTGRES_PASSWORD) if present, and maps those onto
# the PG* variables that psql itself reads. Anything already set in your
# session (e.g. via $env:PGHOST=...) takes priority and is left alone.
if ($env:ENV_FILE) {
    $EnvFile = $env:ENV_FILE
} else {
    $Candidates = @(
        (Join-Path $ProjectRoot ".env"),
        (Join-Path $PSScriptRoot ".env"),
        (Join-Path $ProjectRoot "_env"),
        (Join-Path $PSScriptRoot "_env")
    )
    $Found = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $EnvFile = if ($Found) { $Found } else { Join-Path $ProjectRoot ".env" }
}

if (Test-Path $EnvFile) {
    Write-Host "Loading DB config from $EnvFile"
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $key, $value = $line.Split("=", 2)
            $key = $key.Trim()
            $value = $value.Trim()

            switch ($key) {
                "POSTGRES_HOST"     { if (-not $env:PGHOST)     { $env:PGHOST = $value } }
                "POSTGRES_PORT"     { if (-not $env:PGPORT)     { $env:PGPORT = $value } }
                "POSTGRES_DATABASE" { if (-not $env:PGDATABASE) { $env:PGDATABASE = $value } }
                "POSTGRES_USERNAME" { if (-not $env:PGUSER)     { $env:PGUSER = $value } }
                "POSTGRES_PASSWORD" { if (-not $env:PGPASSWORD) { $env:PGPASSWORD = $value } }
                default             { } # ignore CSV_FILE_PATH, TABLE_NAME, CHUNK_SIZE, etc.
            }
        }
    }
}

# Required: set these in your environment before running (or via the _env
# file above), e.g.:
#   $env:PGHOST="localhost"; $env:PGDATABASE="uber"; $env:PGUSER="postgres"
if (-not $env:PGHOST)     { throw "Set `$env:PGHOST (e.g. `$env:PGHOST='localhost') or add POSTGRES_HOST to $EnvFile" }
if (-not $env:PGPORT)     { $env:PGPORT = "5432" }
if (-not $env:PGDATABASE) { throw "Set `$env:PGDATABASE (e.g. `$env:PGDATABASE='uber') or add POSTGRES_DATABASE to $EnvFile" }
if (-not $env:PGUSER)     { throw "Set `$env:PGUSER (e.g. `$env:PGUSER='postgres') or add POSTGRES_USERNAME to $EnvFile" }

# --- Logging ---
# One brand-new log file per run (not appended), named
# logs\pipeline_YYYY-MM-DD_HH-mm-ss.log, so each run is easy to find and
# read on its own instead of scrolling through one big file. Line format
# matches utils/logger.py: "asctime | levelname-8 | name | message".
$LOG_NAME    = "pipeline"
$DATE_FORMAT = "yyyy-MM-dd HH:mm:ss"

$LogsDir = if ($env:LOGS_DIR) { $env:LOGS_DIR } else { Join-Path $ProjectRoot "logs" }
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}
$RunStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile  = Join-Path $LogsDir "$($LOG_NAME)_$RunStamp.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format $DATE_FORMAT
    $line = "{0} | {1,-8} | {2} | {3}" -f $timestamp, $Level, $LOG_NAME, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding utf8
}

function Invoke-Psql {
    param([string]$SqlFile)
    & $Psql -h $env:PGHOST -p $env:PGPORT -U $env:PGUSER -d $env:PGDATABASE -v ON_ERROR_STOP=1 -f $SqlFile 2>&1 |
        Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed on $SqlFile (exit code $LASTEXITCODE)"
    }
}

function Invoke-Python {
    param([string]$ScriptFile)
    & $Python $ScriptFile 2>&1 | Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptFile failed (exit code $LASTEXITCODE)"
    }
}

try {
    Write-Log "STEP 1/4: Running incremental load (incremental.py)"
    Invoke-Python (Join-Path $ScriptsDir "incremental.py")

    Write-Log "STEP 2/4: Populating dimension tables (09_pop_dims.sql)"
    Invoke-Psql (Join-Path $ModelDir "09_pop_dims.sql")

    Write-Log "STEP 3/4: Populating fact table (10_pop_fact.sql)"
    Invoke-Psql (Join-Path $ModelDir "10_pop_fact.sql")

    Write-Log "STEP 4/4: Running data quality checks (data_quality_checks.py)"
    Invoke-Python (Join-Path $ScriptsDir "data_quality_checks.py")

    Write-Log "Pipeline completed successfully."
}
catch {
    Write-Log -Level "ERROR" -Message "Pipeline FAILED: $($_.Exception.Message)"
    throw
}