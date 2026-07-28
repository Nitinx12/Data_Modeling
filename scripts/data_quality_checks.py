"""
scripts/data_quality_checks.py
================================
Automated version of tests/data_quality_test.sql. Runs the same checks,
but each one returns pass/fail instead of just a number to eyeball —
so this can be wired into a pipeline and stop it on failure.

Tests 1-7 and 10 have a clear expected value (usually 0, or an exact
equality) and are treated as hard pass/fail checks.
Tests 8 and 9 don't have a single correct answer (they're for a human
to sanity-check business logic and date range), so they're only logged,
never fail the run.

Exit code: 0 if all hard checks pass, 1 if any fail.

Run manually:
    uv run scripts/data_quality_checks.py
"""

import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from sqlalchemy import text

from utils.db import get_engine
from utils.logger import get_logger

log = get_logger("data_quality_checks")

RAW_TABLE = os.getenv("TABLE_NAME", "bookings")  # matches incremental.py's TABLE_NAME


def check_row_count_match(engine):
    sql = f'''
        SELECT
            (SELECT COUNT(*) FROM "{RAW_TABLE}") AS source_count,
            (SELECT COUNT(*) FROM fact_bookings) AS fact_count;
    '''
    with engine.begin() as conn:
        row = conn.execute(text(sql)).fetchone()
    passed = row.source_count == row.fact_count
    detail = f"source={row.source_count}, fact={row.fact_count}"
    return "Row count match (source vs fact)", passed, detail


def check_no_duplicate_booking_ids(engine):
    sql = '''
        SELECT COUNT(*) AS dup_count FROM (
            SELECT booking_id FROM fact_bookings GROUP BY booking_id HAVING COUNT(*) > 1
        ) x;
    '''
    with engine.begin() as conn:
        dup_count = conn.execute(text(sql)).scalar()
    return "No duplicate booking_id in fact table", dup_count == 0, f"duplicates={dup_count}"


def check_no_unexpected_null_fks(engine):
    sql = '''
        SELECT
            SUM(CASE WHEN date_key IS NULL THEN 1 ELSE 0 END) AS null_date,
            SUM(CASE WHEN vehicle_type_key IS NULL THEN 1 ELSE 0 END) AS null_vehicle,
            SUM(CASE WHEN payment_method_key IS NULL THEN 1 ELSE 0 END) AS null_payment,
            SUM(CASE WHEN booking_status_key IS NULL THEN 1 ELSE 0 END) AS null_status,
            SUM(CASE WHEN pickup_location_key IS NULL THEN 1 ELSE 0 END) AS null_pickup,
            SUM(CASE WHEN drop_location_key IS NULL THEN 1 ELSE 0 END) AS null_drop
        FROM fact_bookings;
    '''
    with engine.begin() as conn:
        row = conn.execute(text(sql)).fetchone()
    nulls = dict(row._mapping)
    passed = all(v == 0 for v in nulls.values())
    return "No unexpected NULL foreign keys", passed, str(nulls)


def check_no_orphaned_fks(engine):
    sql = '''
        SELECT 'vehicle_type' AS dim, COUNT(*) AS orphaned
        FROM fact_bookings f
        LEFT JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
        WHERE f.vehicle_type_key IS NOT NULL AND vt.vehicle_type_key IS NULL
        UNION ALL
        SELECT 'payment_method', COUNT(*)
        FROM fact_bookings f
        LEFT JOIN dim_payment_method pm ON pm.payment_method_key = f.payment_method_key
        WHERE f.payment_method_key IS NOT NULL AND pm.payment_method_key IS NULL
        UNION ALL
        SELECT 'date', COUNT(*)
        FROM fact_bookings f
        LEFT JOIN dim_date d ON d.date_key = f.date_key
        WHERE f.date_key IS NOT NULL AND d.date_key IS NULL;
    '''
    with engine.begin() as conn:
        rows = conn.execute(text(sql)).fetchall()
    orphaned = {r.dim: r.orphaned for r in rows}
    passed = all(v == 0 for v in orphaned.values())
    return "No orphaned foreign keys", passed, str(orphaned)


def check_dimension_completeness(engine):
    # NOTE: "Date" is stored as TEXT in the raw table, so TO_CHAR needs an
    # explicit ::DATE cast. Payment_Method is COALESCEd to the same
    # 'N/A - Trip Not Completed' placeholder used when populating
    # dim_payment_method, so a NULL source value counts as one distinct
    # bucket on both sides of the comparison instead of being dropped by
    # COUNT(DISTINCT) (which ignores NULLs).
    sql = f'''
        SELECT
            (SELECT COUNT(DISTINCT "Vehicle_Type") FROM "{RAW_TABLE}") AS distinct_vehicle_source,
            (SELECT COUNT(*) FROM dim_vehicle_type) AS rows_in_dim_vehicle,
            (SELECT COUNT(DISTINCT COALESCE("Payment_Method", 'N/A - Trip Not Completed')) FROM "{RAW_TABLE}") AS distinct_payment_source,
            (SELECT COUNT(*) FROM dim_payment_method) AS rows_in_dim_payment,
            (SELECT COUNT(DISTINCT TO_CHAR("Date"::DATE,'YYYYMMDD')) FROM "{RAW_TABLE}") AS distinct_date_source,
            (SELECT COUNT(*) FROM dim_date) AS rows_in_dim_date;
    '''
    with engine.begin() as conn:
        row = conn.execute(text(sql)).fetchone()
    passed = (
        row.distinct_vehicle_source == row.rows_in_dim_vehicle
        and row.distinct_payment_source == row.rows_in_dim_payment
        and row.distinct_date_source == row.rows_in_dim_date
    )
    detail = str(dict(row._mapping))
    return "Dimension completeness (distinct values match)", passed, detail


def check_no_negative_measures(engine):
    sql = '''
        SELECT COUNT(*) AS invalid_measure_rows
        FROM fact_bookings
        WHERE booking_value < 0 OR ride_distance < 0 OR v_tat < 0 OR c_tat < 0;
    '''
    with engine.begin() as conn:
        count = conn.execute(text(sql)).scalar()
    return "No negative measures (fare/distance/TAT)", count == 0, f"invalid_rows={count}"


def check_rating_range(engine):
    sql = '''
        SELECT COUNT(*) AS invalid_rating_rows
        FROM fact_bookings
        WHERE (customer_rating IS NOT NULL AND (customer_rating < 1 OR customer_rating > 5))
           OR (driver_ratings IS NOT NULL AND (driver_ratings < 1 OR driver_ratings > 5));
    '''
    with engine.begin() as conn:
        count = conn.execute(text(sql)).scalar()
    return "Ratings within 1-5 range", count == 0, f"invalid_rows={count}"


def check_location_referential_integrity(engine):
    sql = '''
        SELECT 'pickup' AS role, COUNT(*) AS unmatched
        FROM fact_bookings f
        LEFT JOIN dim_location l ON l.location_key = f.pickup_location_key
        WHERE f.pickup_location_key IS NOT NULL AND l.location_key IS NULL
        UNION ALL
        SELECT 'drop', COUNT(*)
        FROM fact_bookings f
        LEFT JOIN dim_location l ON l.location_key = f.drop_location_key
        WHERE f.drop_location_key IS NOT NULL AND l.location_key IS NULL;
    '''
    with engine.begin() as conn:
        rows = conn.execute(text(sql)).fetchall()
    unmatched = {r.role: r.unmatched for r in rows}
    passed = all(v == 0 for v in unmatched.values())
    return "Pickup/drop location referential integrity", passed, str(unmatched)


# --- Informational only: logged, never fail the pipeline ---

def log_status_flag_consistency(engine):
    sql = '''
        SELECT bs.booking_status,
            SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_customer,
            SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_driver,
            SUM(CASE WHEN f.incomplete_rides_flag THEN 1 ELSE 0 END) AS flagged_incomplete
        FROM fact_bookings f
        JOIN dim_booking_status bs ON bs.booking_status_key = f.booking_status_key
        GROUP BY bs.booking_status
        ORDER BY bs.booking_status;
    '''
    with engine.begin() as conn:
        rows = conn.execute(text(sql)).fetchall()
    log.info("Status/flag consistency (informational, review by eye):")
    for r in rows:
        log.info(f"  {r.booking_status}: {dict(r._mapping)}")


def log_date_range(engine):
    sql = '''
        SELECT MIN(d.full_date) AS min_date, MAX(d.full_date) AS max_date,
               COUNT(DISTINCT d.full_date) AS distinct_days
        FROM fact_bookings f
        JOIN dim_date d ON d.date_key = f.date_key;
    '''
    with engine.begin() as conn:
        row = conn.execute(text(sql)).fetchone()
    log.info(f"Date range (informational): {row.min_date} -> {row.max_date}, {row.distinct_days} distinct days")


HARD_CHECKS = [
    check_row_count_match,
    check_no_duplicate_booking_ids,
    check_no_unexpected_null_fks,
    check_no_orphaned_fks,
    check_dimension_completeness,
    check_no_negative_measures,
    check_rating_range,
    check_location_referential_integrity,
]


def main():
    engine = get_engine()
    log.info("Running data quality checks...")

    results = []
    for check_fn in HARD_CHECKS:
        name, passed, detail = check_fn(engine)
        results.append((name, passed, detail))
        status = "PASS" if passed else "FAIL"
        log_fn = log.info if passed else log.error
        log_fn(f"[{status}] {name} — {detail}")

    log_status_flag_consistency(engine)
    log_date_range(engine)

    failed = [r for r in results if not r[1]]

    print("\n" + "=" * 60)
    print(" DATA QUALITY SUMMARY")
    print("=" * 60)
    for name, passed, detail in results:
        print(f" [{'PASS' if passed else 'FAIL'}] {name}")
    print("=" * 60)

    if failed:
        log.error(f"{len(failed)} of {len(results)} checks FAILED.")
        sys.exit(1)

    log.info(f"All {len(results)} data quality checks passed.")
    sys.exit(0)


if __name__ == "__main__":
    main()