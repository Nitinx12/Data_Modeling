# Docker in This Project

This document explains what Docker does in the UBER ETL pipeline, why each
file exists, and how the pieces fit together at build time and run time.

---

## 1. Why Docker Here

The pipeline needs three things to exist together correctly every time it
runs: a specific Python version and dependency set (via `uv`), a Postgres
database, and a fixed execution order for the ETL steps (load → build
dimensions → build fact table → quality-check). Outside a container, all
three depend on whatever happens to be installed on the machine — a
different Python version, a differently-configured local Postgres, or a
missing `psql` binary will all break the pipeline in ways that are hard to
reproduce and hard to explain to someone else running it.

Docker removes that variability. `docker compose up` gives you the same
Postgres version, the same Python + package versions, and the same 5-step
run sequence, whether it's run on your machine, a teammate's machine, or a
CI runner. Nothing needs to be pre-installed on the host except Docker
itself.

---

## 2. The Two Services

`compose.yml` defines two containers that work together:

| Service    | Image                    | Role                                                                 |
|------------|---------------------------|----------------------------------------------------------------------|
| `db`       | `postgres:16` (official)  | Stores the raw `bookings` table, dimension tables, and fact table.  |
| `pipeline` | built from `Dockerfile`   | Runs the ETL: loads the CSV, builds dims/fact, runs quality checks. |

They're connected by an automatically-created Docker network
(`docker_default`), which is what lets `pipeline` reach `db` by its service
name (`db`) instead of an IP address or `localhost`. `pipeline` is
configured with `depends_on: db: condition: service_healthy`, so it won't
even start until Postgres has passed its healthcheck (`pg_isready`) — this
prevents the classic "container started before the database was ready to
accept connections" race condition.

---

## 3. File-by-File

### `docker/Dockerfile` — builds the `pipeline` image

Multi-stage-style single image, built in layers so Docker can cache
expensive steps and skip them on rebuilds where nothing relevant changed:

1. **Base image**: `python:3.13-slim`, matching the project's `uv`-managed
   interpreter.
2. **System packages**: `postgresql-client` (gives the image the `psql`
   binary, used to run the `.sql` files), `libpq-dev` (gives the image
   `pg_config` and Postgres headers — required to *compile* `psycopg2` from
   source, since this project uses plain `psycopg2`, not the prebuilt
   `psycopg2-binary` wheel), and `build-essential` (a C compiler, needed for
   the same reason).
3. **`uv`**: copied in directly from its own official image
   (`ghcr.io/astral-sh/uv`) rather than installed via `pip`.
4. **Dependency layer, copied first**: `COPY pyproject.toml uv.lock ./`
   followed by `uv sync --frozen --no-install-project`. Copying just these
   two files before the rest of the project means this (slow) layer is only
   re-run when dependencies actually change — editing `scripts/*.py` or
   `model/*.sql` won't invalidate it.
5. **Project layer**: `COPY . .` then `uv sync --frozen` (this second sync
   installs the project itself into the already-built virtual environment).
6. **Entrypoint**: `docker/Entrypoint.sh` is copied in and made executable,
   then set as the container's `ENTRYPOINT` — meaning it's the command that
   runs every time this container starts.

**Build context note**: because `compose.yml` lives in `docker/` but the
project's actual source (`pyproject.toml`, `model/`, `scripts/`, `utils/`)
lives one level up, `compose.yml`'s `build.context` is set to `..` (the
project root) with `dockerfile: docker/Dockerfile`. Every `COPY` in the
Dockerfile is resolved relative to that root, not to the `docker/` folder.

### `UBER/.dockerignore` — controls what gets copied into the image

Lives at the **project root**, not inside `docker/`, because that's where
the build context root is. Its job is to keep the image both smaller and
safer:
- `.env` / `_env` — secrets are never baked into the image; they're
  injected at container start via `compose.yml`'s `environment:` blocks
  instead.
- `.venv/`, `__pycache__/`, `*.pyc` — host-side Python artifacts that would
  conflict with the venv `uv sync` builds fresh inside the image.
- `logs/`, `.git/`, `notebooks/`, `docs/`, `README.md` — not needed at
  runtime, so excluding them keeps the build context (and image) smaller
  and the build faster.

### `docker/compose.yml` — orchestrates both containers together

This is the file you actually run (`docker compose up`). Key jobs:

- **`db` service**: starts Postgres, maps its env vars from your `.env`
  file's names to the names the official Postgres image expects
  (`POSTGRES_USERNAME` → `POSTGRES_USER`, etc.), exposes port 5432 to the
  host so you can connect with an external tool if you want, and persists
  data in a named volume (`pgdata`) so it survives container restarts.
- **`pipeline` service**: builds from the Dockerfile, waits for `db` to be
  healthy, sets every environment variable the pipeline's code needs (see
  §4), and mounts the CSV file plus a `logs/` folder from the host.
- **`volumes:` section**: declares `pgdata` as a named, Docker-managed
  volume. This is what makes `docker compose down` (without `-v`) safe —
  the containers are removed but the actual database files persist. Only
  `docker compose down -v` deletes them.

### `docker/Entrypoint.sh` — the pipeline's run sequence

This is the script that actually executes every time the `pipeline`
container starts. It runs 5 steps in strict order, stopping immediately on
any failure (`set -euo pipefail` plus `psql -v ON_ERROR_STOP=1`):

| Step | What runs                                    | Why |
|------|-----------------------------------------------|-----|
| 0/5  | `model/01_*.sql` through `model/08_*.sql`     | Creates the dimension tables and fact table schema (DDL). Runs every time; safe because these use `CREATE TABLE IF NOT EXISTS`. |
| 1/5  | `scripts/incremental.py`                      | Loads new rows from the mounted CSV into the `bookings` table, skipping duplicates. |
| 2/5  | `model/09_pop_dims.sql`                       | Populates the dimension tables from distinct values in `bookings`. |
| 3/5  | `model/10_pop_fact.sql`                       | Populates the fact table, joining `bookings` against the now-populated dimensions. |
| 4/5  | `scripts/data_quality_checks.py`              | Runs 8 checks (row-count match, no duplicate keys, no orphaned foreign keys, valid ranges, etc.) and reports pass/fail. |

Every step's combined stdout/stderr is mirrored to both the console and a
fresh timestamped file in `logs/` (`pipeline_YYYY-MM-DD_HH-MM-SS.log`), via
a small `tee`-based logging helper — matching what `ps1/pipeline.ps1` does
natively on Windows.

---

## 4. Environment Variables — three naming conventions, one set of values

This project's code reads Postgres connection details under **three
different variable name conventions**, because different libraries have
different conventions. All three need to resolve to the same actual
values, so `compose.yml`'s `pipeline.environment:` block sets all three:

| Convention                                  | Used by                                             | Set to |
|-----------------------------------------------|------------------------------------------------------|--------|
| `PGHOST` / `PGPORT` / `PGDATABASE` / `PGUSER` / `PGPASSWORD` | `psql` (native env vars it reads automatically)      | `db`, `5432`, and values from `.env` |
| `POSTGRES_HOST` / `POSTGRES_PORT` / `POSTGRES_DATABASE` / `POSTGRES_USERNAME` / `POSTGRES_PASSWORD` | `utils/db.py`, used by `incremental.py` and `data_quality_checks.py` via SQLAlchemy | `db`, `5432`, and values from `.env` |
| `PGOPTIONS`                                    | Applied by libpq at connection time — affects *both* `psql` and psycopg2 | `-c datestyle=ISO,DMY` |

**Why `PGHOST`/`POSTGRES_HOST` are hardcoded to `db`, not read from
`.env`**: inside the Compose network, containers reach each other by
*service name*. Your `.env` file's `POSTGRES_HOST=localhost` (correct for
running the pipeline natively on Windows against a local Postgres install)
would, inside the `pipeline` container, point back at the `pipeline`
container itself — which has no Postgres server running on it. `db` is the
one value that resolves correctly, from inside the Docker network, to the
actual Postgres container.

**Why `PGOPTIONS` exists**: the source CSV's date column is formatted
`DD-MM-YYYY` (e.g. `26-07-2024`). Postgres's default date-parsing order is
`MDY` (US-style), which misreads `26` as a month and errors with "date/time
field value out of range." `PGOPTIONS="-c datestyle=ISO,DMY"` is a standard
libpq environment variable that gets applied at connection startup — before
any query can run — telling Postgres to parse ambiguous dates day-first
instead. It's set once in `Entrypoint.sh` and inherited by every child
process the script spawns (both `psql` calls and the Python scripts).

---

## 5. Volumes and Persistence

| Volume                              | Type            | Purpose |
|---------------------------------------|------------------|---------|
| `pgdata:/var/lib/postgresql/data`     | named (Docker-managed) | Postgres's actual data files. Survives `docker compose down`; only deleted by `docker compose down -v`. |
| `${CSV_HOST_PATH}:/data/Bookings.csv:ro` | bind mount (host path) | Makes your local CSV visible inside the `pipeline` container, read-only. Path comes from `.env`, not hardcoded, so it works regardless of where the file lives on your machine. |
| `./logs:/app/logs`                    | bind mount (relative host path) | Mirrors the container's log output back to `docker/logs/` on your machine, so you can inspect run history without opening a shell into the container. |

---

## 6. Common Commands

Run from inside the `docker/` folder (where `compose.yml` and `.env` live):

```bash
# First run, or after changing the Dockerfile / pyproject.toml / uv.lock
docker compose up --build

# Subsequent runs — reuses the already-built image, just re-executes the pipeline
docker compose up

# Re-run only the pipeline on demand, without restarting/recreating db
docker compose run --rm pipeline

# Start only Postgres, e.g. to inspect data with an external client
docker compose up --build db

# Stop everything, keep the database data
docker compose down

# Stop everything AND wipe the database data (full clean slate)
docker compose down -v
```

---

## 7. Known Gotchas (and why the fixes look the way they do)

These are worth knowing if you ever need to modify `Dockerfile`,
`compose.yml`, or `Entrypoint.sh`:

- **Build context vs. Dockerfile location**: because `compose.yml` sits in
  `docker/` but the code it needs to `COPY` sits in the project root,
  `context: ..` and `dockerfile: docker/Dockerfile` must stay paired
  together. Changing one without the other breaks the build.
- **`.dockerignore` only works from the context root.** If it's ever moved
  back into `docker/`, Docker will silently stop applying it (no error —
  it just won't exclude anything), and secrets/artifacts could leak into
  the image.
- **`psycopg2` (not `-binary`) needs `libpq-dev` to compile.** Removing
  that package from the `apt-get install` line will bring back a
  `pg_config executable not found` build failure.
- **Schema creation (step 0) assumes idempotent DDL.** If any of
  `model/01_*.sql` through `08_*.sql` are changed to use plain
  `CREATE TABLE` instead of `CREATE TABLE IF NOT EXISTS`, re-running the
  pipeline against an existing database will start failing on the second
  run.
- **Windows paths in `compose.yml` should always go through `.env`
  (`CSV_HOST_PATH`), with forward slashes**, never hardcoded directly into
  `compose.yml` with backslashes — the volume syntax parses on `:`, which
  collides with a Windows drive letter and backslashes.