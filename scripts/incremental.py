"""
Incremental CSV -> PostgreSQL loader
=====================================
Loads Bookings.csv into Postgres. "Incremental" is enforced on the
Booking_ID column: it's used as the table's PRIMARY KEY, and every load
runs an INSERT ... ON CONFLICT (Booking_ID) DO NOTHING, so:

  - Rows whose Booking_ID is already in the table are skipped.
  - Only genuinely new Booking_IDs get inserted.
  - You can re-run this script (e.g. daily/hourly on a refreshed CSV)
    and it will never duplicate data.

Config comes from a .env file next to this script:
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DATABASE,
    POSTGRES_USERNAME, POSTGRES_PASSWORD
    CSV_FILE_PATH   - path to Bookings.csv
    TABLE_NAME      - target table (default: bookings)
    CHUNK_SIZE      - rows per batch (default: 5000)

Run:
    pip install -r requirements.txt
    python incremental_load.py
"""

import os
import sys
import time

# Make sure the project root (parent of this script's folder) is importable,
# so `utils/` resolves correctly no matter where this script is run from.
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

from utils.logger import get_logger

load_dotenv()

# ---------------- Config ----------------
PG_HOST = os.getenv("POSTGRES_HOST", "localhost")
PG_PORT = os.getenv("POSTGRES_PORT", "5432")
PG_DB = os.getenv("POSTGRES_DATABASE", "postgres")
PG_USER = os.getenv("POSTGRES_USERNAME", "postgres")
PG_PASS = os.getenv("POSTGRES_PASSWORD", "")

CSV_FILE_PATH = os.getenv(
    "CSV_FILE_PATH",
    r"C:\Users\91852\OneDrive\Desktop\Github Repo\Booking_data\datasets\data\Bookings.csv",
)
TABLE_NAME = os.getenv("TABLE_NAME", "bookings")
KEY_COLUMN = "Booking_ID"  # must match the CSV header exactly (after sanitizing)
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "5000"))
LOG_TABLE = "etl_load_log"

log = get_logger("incremental_loader")

PG_TYPE_MAP = {
    "int64": "BIGINT",
    "float64": "DOUBLE PRECISION",
    "bool": "BOOLEAN",
    "datetime64[ns]": "TIMESTAMP",
    "object": "TEXT",
}


def get_engine():
    url = f"postgresql+psycopg2://{PG_USER}:{PG_PASS}@{PG_HOST}:{PG_PORT}/{PG_DB}"
    return create_engine(url)


def sanitize_columns(columns):
    """Make CSV headers safe/consistent Postgres column names."""
    return [c.strip().replace(" ", "_") for c in columns]


def infer_schema(df):
    return [f'"{col}" {PG_TYPE_MAP.get(str(dtype), "TEXT")}' for col, dtype in df.dtypes.items()]


def ensure_tables(engine, df):
    if KEY_COLUMN not in df.columns:
        log.error(f"Key column '{KEY_COLUMN}' not found in CSV columns: {list(df.columns)}")
        sys.exit(1)

    cols_sql = infer_schema(df)
    create_sql = f'''
        CREATE TABLE IF NOT EXISTS "{TABLE_NAME}" (
            {", ".join(cols_sql)},
            _loaded_at TIMESTAMP DEFAULT now(),
            PRIMARY KEY ("{KEY_COLUMN}")
        );
    '''
    log_sql = f'''
        CREATE TABLE IF NOT EXISTS "{LOG_TABLE}" (
            id SERIAL PRIMARY KEY,
            run_at TIMESTAMP DEFAULT now(),
            rows_read INTEGER,
            rows_inserted INTEGER,
            rows_skipped INTEGER,
            source_file TEXT
        );
    '''
    with engine.begin() as conn:
        conn.execute(text(create_sql))
        conn.execute(text(log_sql))


def get_row_count(engine, table_name):
    """Returns current row count of a table, or 0 if it doesn't exist yet."""
    check_sql = "SELECT to_regclass(:t)"
    with engine.begin() as conn:
        exists = conn.execute(text(check_sql), {"t": table_name}).scalar()
        if exists is None:
            return 0
        return conn.execute(text(f'SELECT COUNT(*) FROM "{table_name}"')).scalar()


def load_incremental(engine, csv_path):
    total_read = 0
    total_inserted = 0
    first_chunk = True
    staging_table = f"_staging_{TABLE_NAME}"

    for chunk in pd.read_csv(csv_path, chunksize=CHUNK_SIZE):
        chunk.columns = sanitize_columns(chunk.columns)

        if first_chunk:
            ensure_tables(engine, chunk)
            first_chunk = False

        total_read += len(chunk)

        # Stage the chunk, then upsert with ON CONFLICT DO NOTHING so
        # re-running the script is always safe / idempotent.
        chunk.to_sql(staging_table, engine, if_exists="replace", index=False)

        col_list = ", ".join(f'"{c}"' for c in chunk.columns)
        upsert_sql = f'''
            INSERT INTO "{TABLE_NAME}" ({col_list})
            SELECT {col_list} FROM "{staging_table}"
            ON CONFLICT ("{KEY_COLUMN}") DO NOTHING;
        '''
        with engine.begin() as conn:
            result = conn.execute(text(upsert_sql))
            inserted = result.rowcount or 0
            total_inserted += inserted
            conn.execute(text(f'DROP TABLE IF EXISTS "{staging_table}"'))

        log.info(f"Chunk done: read={len(chunk)}, newly_inserted={inserted}")

    return total_read, total_inserted, total_read - total_inserted


def log_run(engine, rows_read, rows_inserted, rows_skipped, source_file):
    with engine.begin() as conn:
        conn.execute(
            text(f'''
                INSERT INTO "{LOG_TABLE}" (rows_read, rows_inserted, rows_skipped, source_file)
                VALUES (:r, :i, :s, :f)
            '''),
            {"r": rows_read, "i": rows_inserted, "s": rows_skipped, "f": source_file},
        )


def print_summary(previous_count, rows_read, rows_inserted, rows_skipped, new_count, duration):
    lines = [
        "",
        "=" * 50,
        " LOAD SUMMARY".ljust(50),
        "=" * 50,
        f" Table                 : {TABLE_NAME}",
        f" Rows in table before  : {previous_count}",
        f" Rows read from CSV    : {rows_read}",
        f" Rows newly inserted   : {rows_inserted}",
        f" Rows skipped (dupes)  : {rows_skipped}",
        f" Rows in table after   : {new_count}",
        f" Duration              : {duration:.2f} sec",
        "=" * 50,
        "",
    ]
    summary_text = "\n".join(lines)
    print(summary_text)
    log.info(summary_text)


def main():
    if not os.path.exists(CSV_FILE_PATH):
        log.error(f"CSV file not found: {CSV_FILE_PATH}")
        sys.exit(1)

    log.info(f"Starting incremental load: {CSV_FILE_PATH} -> table '{TABLE_NAME}'")
    engine = get_engine()

    start_time = time.time()
    previous_count = get_row_count(engine, TABLE_NAME)

    rows_read, rows_inserted, rows_skipped = load_incremental(engine, CSV_FILE_PATH)
    log_run(engine, rows_read, rows_inserted, rows_skipped, CSV_FILE_PATH)

    new_count = get_row_count(engine, TABLE_NAME)
    duration = time.time() - start_time

    log.info(
        f"Finished. rows_read={rows_read}, newly_inserted={rows_inserted}, "
        f"already_existed/skipped={rows_skipped}"
    )
    print_summary(previous_count, rows_read, rows_inserted, rows_skipped, new_count, duration)


if __name__ == "__main__":
    main()