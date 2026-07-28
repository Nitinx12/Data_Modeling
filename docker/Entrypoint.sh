#!/usr/bin/env bash
# =====================================================================
# entrypoint.sh — container equivalent of ps1/pipeline.ps1
#
# Runs the same 4 steps, in the same order:
#   1. scripts/incremental.py
#   2. model/09_pop_dims.sql   (via psql)
#   3. model/10_pop_fact.sql   (via psql)
#   4. scripts/data_quality_checks.py
#
# `set -euo pipefail` stops at the first failure, same guarantee as the
# PowerShell version's $ErrorActionPreference + exit-code checks.
#
# Config: PGHOST / PGPORT / PGDATABASE / PGUSER / PGPASSWORD, same as
# psql itself reads. Pass these with `docker run -e` or an --env-file
# (see notes at the bottom of this file for the POSTGRES_* -> PG* naming
# mismatch with your existing .env).
# =====================================================================
set -euo pipefail

PROJECT_ROOT="/app"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
MODEL_DIR="$PROJECT_ROOT/model"
LOGS_DIR="$PROJECT_ROOT/logs"

mkdir -p "$LOGS_DIR"
LOG_FILE="$LOGS_DIR/pipeline_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Mirrors pipeline.ps1: fresh timestamped log file every run (no
# appending), format "asctime | LEVEL    | pipeline | message", plus
# console output — matching utils/logger.py's line format.
log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') | INFO     | pipeline | $1"
    printf '\n%s\n' "$line"
    printf '\n%s\n' "$line" >> "$LOG_FILE"
}

# Runs a command, sending its combined stdout+stderr to both the console
# and the log file (same effect as Tee-Object in the PowerShell version).
run_logged() {
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

: "${PGHOST:?Set PGHOST, e.g. -e PGHOST=host.docker.internal}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?Set PGDATABASE, e.g. -e PGDATABASE=Uber}"
: "${PGUSER:?Set PGUSER, e.g. -e PGUSER=postgres}"
# PGPASSWORD intentionally not required here — psql reads it directly
# from the environment if set.

run_psql() {
    run_logged psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -f "$1"
}

log "STEP 1/4: Running incremental load (incremental.py)"
run_logged python "$SCRIPTS_DIR/incremental.py"

log "STEP 2/4: Populating dimension tables (09_pop_dims.sql)"
run_psql "$MODEL_DIR/09_pop_dims.sql"

log "STEP 3/4: Populating fact table (10_pop_fact.sql)"
run_psql "$MODEL_DIR/10_pop_fact.sql"

log "STEP 4/4: Running data quality checks (data_quality_checks.py)"
run_logged python "$SCRIPTS_DIR/data_quality_checks.py"

log "Pipeline completed successfully."

# -----------------------------------------------------------------
# NOTE on CSV_FILE_PATH: your .env has a Windows path
#   CSV_FILE_PATH=C:\Users\91852\...\Bookings.csv
# which doesn't exist inside the container. Mount the CSV in via
# `docker run -v`, then override CSV_FILE_PATH to the Linux mount
# path, e.g.:
#   docker run -v /path/on/host/Bookings.csv:/data/Bookings.csv \
#              -e CSV_FILE_PATH=/data/Bookings.csv ...
# -----------------------------------------------------------------