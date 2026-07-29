# syntax=docker/dockerfile:1

# ASSUMPTION: Python 3.13, based on the uv-managed interpreter seen in your
# logs (cpython-3.13-windows-x86_64). Check .python-version and change the
# tag below if it's actually a different version.
FROM python:3.13-slim AS base

# --- System dependencies ---
# postgresql-client gives us `psql`, which model/09_pop_dims.sql and
# model/10_pop_fact.sql are run through (same as pipeline.ps1 does on
# Windows). build-essential covers any package in uv.lock that needs to
# compile from source (e.g. psycopg2 without the -binary wheel).
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# --- uv ---
# Installs uv itself (the project uses pyproject.toml + uv.lock, not plain
# pip/requirements.txt).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Copy dependency files first so Docker can cache this layer — deps only
# get reinstalled when pyproject.toml/uv.lock actually change, not on
# every code edit.
#
# NOTE: this Dockerfile lives in docker/, but the build context (set in
# compose.yml as `context: ..`) is the project root, UBER/. So every COPY
# below is relative to UBER/, not to docker/.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# Now copy the rest of the project
COPY . .
RUN uv sync --frozen

# Make `uv run <cmd>` the implicit way things execute, so the venv uv
# creates is always used without needing to activate it manually.
ENV PATH="/app/.venv/bin:$PATH"

# --- Runtime ---
# Runs the same 4 steps as ps1/pipeline.ps1, translated to bash:
#   1. incremental.py, 2. 09_pop_dims.sql, 3. 10_pop_fact.sql, 4. data_quality_checks.py
#
# Source path matches the real repo layout: UBER/docker/Entrypoint.sh
# (capital E — Linux is case-sensitive, this has to match exactly).
COPY docker/Entrypoint.sh /app/docker/entrypoint.sh
RUN chmod +x /app/docker/entrypoint.sh

ENTRYPOINT ["/app/docker/entrypoint.sh"]