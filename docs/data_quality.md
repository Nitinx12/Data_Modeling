# ETL Data Quality Tests

This document explains the 10 SQL checks used to validate that data loaded correctly from the raw `booking` table into the star schema (`fact_bookings` + `dim_*`). Each test targets a different way an ETL load can silently go wrong — most failures here don't throw an error, they just quietly produce wrong numbers in your reports.

> **Note on table naming**: these tests query a table called `booking` (singular). Earlier in this project the raw landing table was created as `bookings` (plural) — before running these, confirm which name your raw table actually has and adjust the queries if needed, otherwise Test 1 and Test 5 will fail with "relation does not exist".

## Why bother testing an ETL load at all?

A load can "succeed" (no errors, script exits 0) while still being wrong in ways that only show up later — a dashboard showing 2% fewer bookings than it should, ratings that are impossible, or cancelled rides marked as completed. These tests catch that class of bug immediately after a load, rather than someone noticing weeks later that a report looks off.

Each test below is one of five categories:

| Category | Tests | Catches |
|---|---|---|
| Completeness | 1, 5 | Rows or dimension values that got silently dropped |
| Uniqueness | 2 | Duplicate loads |
| Referential integrity | 3, 4, 10 | Broken or missing links between fact and dimension tables |
| Value sanity | 6, 7 | Impossible numbers (negative values, out-of-range ratings) |
| Business logic | 8, 9 | Numbers that are individually valid but inconsistent with each other |

---

## Test 1 — Row count match (source vs. fact)

```sql
SELECT (SELECT COUNT(*) FROM booking) AS source_count,
       (SELECT COUNT(*) FROM fact_bookings) AS fact_count;
```

**What it checks**: the raw table and the fact table have the same number of rows.

**Why it matters**: `fact_bookings` should have exactly one row per booking, same as the raw table. If `fact_count < source_count`, rows were lost during the load — almost always because an `INNER JOIN` to a dimension table failed to match (e.g. a `Vehicle_Type` value existed in `booking` but not yet in `dim_vehicle_type`), silently dropping that row instead of erroring.

**Expected result**: `source_count = fact_count`.

---

## Test 2 — Duplicate `booking_id` in the fact table

```sql
SELECT booking_id, COUNT(*) AS cnt
FROM fact_bookings
GROUP BY booking_id
HAVING COUNT(*) > 1;
```

**What it checks**: no `booking_id` appears more than once.

**Why it matters**: `booking_id` defines the *grain* of the fact table (one row = one booking). If the load logic ever inserts instead of upserts, or the same source file gets loaded twice, the same booking will be double-counted in every downstream sum (revenue, ride counts, etc.).

**Expected result**: zero rows returned. Any row returned here is a duplicate that needs investigating.

---

## Test 3 — Unexpected NULLs in foreign keys

```sql
SELECT 
    SUM(CASE WHEN date_key IS NULL THEN 1 ELSE 0 END) AS null_date,
    SUM(CASE WHEN vehicle_type_key IS NULL THEN 1 ELSE 0 END) AS null_vehicle,
    SUM(CASE WHEN payment_method_key IS NULL THEN 1 ELSE 0 END) AS null_payment,
    SUM(CASE WHEN booking_status_key IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN pickup_location_key IS NULL THEN 1 ELSE 0 END) AS null_pickup,
    SUM(CASE WHEN drop_location_key IS NULL THEN 1 ELSE 0 END) AS null_drop
FROM fact_bookings;
```

**What it checks**: counts how many fact rows have a missing key for each dimension.

**Why it matters**: a NULL foreign key almost always means the lookup during the transform failed to find a matching dimension row — commonly caused by a typo, trailing whitespace, or case mismatch between the raw text value and what's stored in the dimension table (e.g. `"cash"` in `booking` vs. `"Cash"` in `dim_payment_method`).

**Expected result**: all counts should be 0 — *except* `incomplete_reason_key`, which is genuinely supposed to be NULL for any ride that wasn't cancelled or incomplete. That one column isn't checked here on purpose, but note that a non-zero count for any of the *other* five columns is a real problem.

---

## Test 4 — Orphaned foreign keys

```sql
SELECT 'vehicle_type' AS dim, COUNT(*) AS orphaned
FROM fact_bookings f
LEFT JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
WHERE f.vehicle_type_key IS NOT NULL AND vt.vehicle_type_key IS NULL
-- ...repeated for payment_method and date
```

**What it checks**: every non-NULL foreign key in `fact_bookings` actually points to a row that exists in the corresponding dimension table.

**Why it matters**: this is different from Test 3. A NULL key means the lookup failed and nothing was stored. An *orphaned* key means something WAS stored, but it points to a dimension row that doesn't exist (or has since been deleted). This normally can't happen if the `FOREIGN KEY` constraints are active — this test exists to catch it if constraints were ever dropped, disabled, or bypassed (e.g. a bulk load that skips constraint checks).

**Expected result**: `orphaned = 0` for every dimension checked.

---

## Test 5 — Dimension completeness (distinct value count match)

```sql
SELECT 
    (SELECT COUNT(DISTINCT "Vehicle_Type") FROM booking) AS distinct_vehicle_source,
    (SELECT COUNT(*) FROM dim_vehicle_type) AS rows_in_dim_vehicle,
    (SELECT COUNT(DISTINCT "Payment_Method") FROM booking) AS distinct_payment_source,
    (SELECT COUNT(*) FROM dim_payment_method) AS rows_in_dim_payment,
    (SELECT COUNT(DISTINCT TO_CHAR("Date",'YYYYMMDD')) FROM booking) AS distinct_date_source,
    (SELECT COUNT(*) FROM dim_date) AS rows_in_dim_date;
```

**What it checks**: the number of distinct values in the raw source matches the number of rows in the corresponding dimension table.

**Why it matters**: dimensions are usually populated by scanning the raw data for distinct values and inserting any that are new. If that step has a bug (e.g. it only runs once and never picks up new values added later), the dimension silently falls behind — new vehicle types or dates appear in the source but never get a row in the dimension, which then causes Test 3/4 failures downstream. This test catches that gap directly, at the dimension level rather than the fact level.

**Expected result**: `distinct_..._source = rows_in_dim_...` for each pair. If the dimension has *fewer* rows than the source has distinct values, something never made it into the dimension table.

---

## Test 6 — Measure sanity check (no negative values)

```sql
SELECT COUNT(*) AS invalid_measure_rows
FROM fact_bookings
WHERE booking_value < 0 OR ride_distance < 0 OR v_tat < 0 OR c_tat < 0;
```

**What it checks**: fare, distance, and turnaround-time columns are never negative.

**Why it matters**: these are all real-world quantities that can't logically be negative. A negative value here signals a data type problem, a bad unit conversion, or corrupted source data — not something a report should silently sum together with valid rows.

**Expected result**: 0 rows.

---

## Test 7 — Rating range check

```sql
SELECT COUNT(*) AS invalid_rating_rows
FROM fact_bookings
WHERE (customer_rating IS NOT NULL AND (customer_rating < 1 OR customer_rating > 5))
   OR (driver_ratings IS NOT NULL AND (driver_ratings < 1 OR driver_ratings > 5));
```

**What it checks**: any non-NULL rating falls within the valid 1–5 scale.

**Why it matters**: ratings outside 1–5 are physically impossible on this platform's scale — a `0`, a `6`, or a `-1` rating points to a casting bug (e.g. treating a missing-value placeholder like `-1` or `0` as a real rating instead of NULL).

**Expected result**: 0 rows.

---

## Test 8 — Booking status / flag consistency

```sql
SELECT bs.booking_status, 
    SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_customer,
    SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_driver,
    SUM(CASE WHEN f.incomplete_rides_flag THEN 1 ELSE 0 END) AS flagged_incomplete
FROM fact_bookings f
JOIN dim_booking_status bs ON bs.booking_status_key = f.booking_status_key
GROUP BY bs.booking_status
ORDER BY bs.booking_status;
```

**What it checks**: whether the boolean flags on each row line up with what the row's `booking_status` says.

**Why it matters**: this is a *business logic* check, not a data type check — every individual value here could be technically valid, yet still be wrong together. A row with `booking_status = 'Completed'` should have all three flags `false`; if this query shows non-zero flag counts under "Completed", the ETL transform has a logic bug in how it derives those flags from the raw status/reason columns, not a data quality problem in the source.

**Expected result**: no output row for a "clean" status (like Completed) should have non-zero flag counts. You're reading this table by eye rather than expecting a single pass/fail number.

---

## Test 9 — Date range sanity check

```sql
SELECT MIN(d.full_date) AS min_date, MAX(d.full_date) AS max_date, COUNT(DISTINCT d.full_date) AS distinct_days
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key;
```

**What it checks**: the actual date range represented in the fact table.

**Why it matters**: this doesn't have a fixed pass/fail condition — you compare the output against what you *know* the source data should cover (e.g. "this file should only contain July 2024 bookings"). If `max_date` shows a date far outside the expected range, it usually points to a date-parsing bug (wrong format string, e.g. reading `DD/MM/YYYY` as `MM/DD/YYYY`).

**Expected result**: `min_date`/`max_date` match the known range of your source file; `distinct_days` roughly matches the number of days that range should span.

---

## Test 10 — Pickup/drop location referential check

```sql
SELECT 'pickup' AS role, COUNT(*) AS unmatched
FROM fact_bookings f
LEFT JOIN dim_location l ON l.location_key = f.pickup_location_key
WHERE f.pickup_location_key IS NOT NULL AND l.location_key IS NULL

UNION ALL

SELECT 'drop', COUNT(*)
FROM fact_bookings f
LEFT JOIN dim_location l ON l.location_key = f.drop_location_key
WHERE f.drop_location_key IS NOT NULL AND l.location_key IS NULL;
```

**What it checks**: same idea as Test 4 (orphaned FK), but specifically for `dim_location`, because it's a **role-playing dimension** — the same table is referenced twice (once for pickup, once for drop) via two different foreign keys.

**Why it matters**: role-playing dimensions are a common place for referential bugs to hide, because it's easy for a transform script to correctly join one role (say, pickup) and forget to apply the same lookup logic to the other (drop), or vice versa. Testing both roles separately makes sure neither one was missed.

**Expected result**: `unmatched = 0` for both `pickup` and `drop`.

---

## Suggested workflow

Run these after every load of `fact_bookings`, in this order:

1. **Tests 1, 2** — confirm the load didn't drop or duplicate rows at all.
2. **Tests 3, 4, 5, 10** — confirm every dimension link is complete and correct.
3. **Tests 6, 7** — confirm the raw numbers are sane.
4. **Tests 8, 9** — eyeball business logic and date range for anything that looks "technically valid but wrong".

If 1–5 and 10 aren't all clean, don't bother interpreting 6–9 yet — a broken join upstream can make later numbers look wrong for reasons that have nothing to do with the actual data.