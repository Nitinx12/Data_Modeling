# Incremental Bookings Loader

Loads `Bookings.csv` into a Postgres table, skipping any rows that were already loaded in a previous run. Safe to re-run as many times as you want — it will never create duplicate rows.

## Folder structure

```
C:\UBER\
├── scripts\
│   └── incremental.py       <- main script
├── utils\
│   ├── __init__.py
│   └── logger.py            <- shared logging setup
├── logs\                    <- log files land here automatically
├── .env                     <- Postgres + CSV config
└── requirements.txt
```

## How the incremental logic works

The core idea: **`Booking_ID` is the table's PRIMARY KEY.**

1. On first run, the script reads the CSV, infers a column type for each field, and creates the table (`CREATE TABLE IF NOT EXISTS`) with `Booking_ID` set as `PRIMARY KEY`.
2. On every run (first or later), the CSV is read in chunks (default 5,000 rows) to keep memory usage low even on large files.
3. Each chunk is written to a temporary **staging table** in Postgres.
4. The script then runs:
   ```sql
   INSERT INTO bookings (...)
   SELECT ... FROM _staging_bookings
   ON CONFLICT (Booking_ID) DO NOTHING;
   ```
   - If a `Booking_ID` **already exists** in `bookings`, Postgres silently skips that row.
   - If a `Booking_ID` is **new**, it gets inserted.
5. The staging table is dropped after each chunk.

This means:
- You can drop a fresh `Bookings.csv` (with old + new rows mixed together) in the same file path and re-run the script — only the genuinely new bookings get added.
- No separate "last processed ID" or timestamp tracking is needed, because Postgres itself enforces uniqueness on `Booking_ID`.

## Config (`.env`)

```dotenv
# Postgres configuration
POSTGRES_HOST=your_host
POSTGRES_PORT=your_port
POSTGRES_DATABASE=your_database
POSTGRES_USERNAME=your_username
POSTGRES_PASSWORD=your_password

# Source CSV and target table
CSV_FILE_PATH=path\to\your\Bookings.csv
TABLE_NAME=bookings
CHUNK_SIZE=5000
```

| Variable | Purpose | Default |
|---|---|---|
| `POSTGRES_HOST/PORT/DATABASE/USERNAME/PASSWORD` | DB connection | — |
| `CSV_FILE_PATH` | Path to the source CSV | hardcoded fallback path in script |
| `TABLE_NAME` | Target table name | `bookings` |
| `CHUNK_SIZE` | Rows read/inserted per batch | `5000` |

## Running it

Using `uv`:

```powershell
cd C:\UBER
uv pip install -r requirements.txt
uv run scripts\incremental.py
```

If you'd rather manage dependencies via `pyproject.toml` instead of `requirements.txt`:

```powershell
uv add pandas sqlalchemy psycopg2-binary python-dotenv
uv run scripts\incremental.py
```

`uv run` automatically uses the project's `.venv`, so there's no need to manually activate it first.

The script also adds the project root to `sys.path` automatically, so it works no matter what your current directory is when you run it — `utils/logger.py` will always be found.

## What you'll see: the summary block

At the end of every run, both printed to console and written to the log file:

```
==================================================
 LOAD SUMMARY
==================================================
 Table                 : bookings
 Rows in table before  : 100000
 Rows read from CSV    : 100500
 Rows newly inserted   : 500
 Rows skipped (dupes)  : 100000
 Rows in table after   : 100500
 Duration              : 3.42 sec
==================================================
```

| Field | Meaning |
|---|---|
| Rows in table before | `COUNT(*)` in Postgres before this run started |
| Rows read from CSV | Total rows pulled out of the CSV file |
| Rows newly inserted | New `Booking_ID`s that got added this run |
| Rows skipped (dupes) | Rows whose `Booking_ID` already existed |
| Rows in table after | `COUNT(*)` in Postgres after the run finished |
| Duration | Wall-clock time for the whole run |

## Logging (`utils/logger.py`)

- Every run writes to **both** the console and a file under `logs/`.
- One log file per day: `logs/incremental_loader_YYYY-MM-DD.log`.
- Files auto-rotate at 5 MB (keeps up to 5 backups), so `logs/` never grows unbounded.
- Log format:
  ```
  2026-07-28 14:32:10 | INFO | incremental_loader | Chunk done: read=5000, newly_inserted=120
  ```

## Audit trail in Postgres (`etl_load_log` table)

Separately from the log files, every run also inserts one row into an `etl_load_log` table:

| Column | Description |
|---|---|
| `run_at` | Timestamp of the run |
| `rows_read` | Rows read from CSV |
| `rows_inserted` | New rows inserted |
| `rows_skipped` | Duplicate rows skipped |
| `source_file` | Path of the CSV used |

Query it any time to see load history:
```sql
SELECT * FROM etl_load_log ORDER BY run_at DESC;
```

## Troubleshooting

**`ModuleNotFoundError: No module named 'utils'`**
Happens if `utils/` isn't a sibling of the project root the script auto-detects (parent of `scripts/`). Confirm the folder tree matches the layout above — `utils/` and `logs/` should sit directly under `C:\UBER\`, not inside `scripts\`.

**`Key column 'Booking_ID' not found in CSV columns`**
The CSV header must literally be `Booking_ID` (case-sensitive) after underscores replace spaces. Check the first row of `Bookings.csv`.

**Table already exists with different columns**
The script only runs `CREATE TABLE IF NOT EXISTS` — it won't alter an existing table's schema. If your CSV's columns change, drop/recreate the table manually or add a migration step.