# Architecture: Data Modeling

This document explains *how* the data model for this project was designed — not just what the tables are (see `model.md` for that), but the modeling methodology behind them, the design decisions made at each step, and the tradeoffs those decisions carry.

## 1. Modeling approach: dimensional modeling (star schema)

This project uses **Kimball-style dimensional modeling** rather than a fully normalized (3NF) schema. The reasoning:

| | 3NF (normalized) | Star schema (this project) |
|---|---|---|
| Optimized for | Transactional writes, no redundancy | Analytical reads, fast aggregation |
| Joins needed for a typical report | Many, often nested | One "hop" from fact to each dimension |
| Query pattern here | N/A — this isn't a transactional system | "Total revenue by vehicle type, by day, by payment method" — exactly what a star schema is built for |

Since this project exists to answer business questions (`sql/01`–`10`), not to process live bookings, a star schema trades some storage/redundancy for much simpler, faster analytical queries.

## 2. The four-step dimensional modeling process

Kimball's methodology defines a model in four steps, in a fixed order. Here's how each was applied:

### Step 1 — Select the business process
**Bookings.** Not "customers", not "drivers" — the atomic business event being modeled is a single ride booking. This choice drives everything downstream.

### Step 2 — Declare the grain
**One row in `fact_bookings` = one booking**, identified by `booking_id`. This is the single most important decision in the whole model — every dimension and measure has to be true *at this grain*. It's also why `fact_bookings.booking_id` is a `PRIMARY KEY`: the grain-defining column is enforced structurally, not just by convention.

### Step 3 — Identify the dimensions
Everything you'd want to "slice by" when analyzing a booking:

| Dimension | Answers |
|---|---|
| `dim_date` | *When* (calendar attributes) |
| `dim_time` | *What time of day* |
| `dim_vehicle_type` | *What kind of vehicle* |
| `dim_payment_method` | *How it was paid for* |
| `dim_booking_status` | *What happened to it* |
| `dim_location` (×2 roles) | *Where from / where to* |
| `dim_cancellation_reason` | *Why it failed*, when applicable |

### Step 4 — Identify the facts (measures)
The numeric, analyzable values that live directly on `fact_bookings`: `booking_value`, `ride_distance`, `customer_rating`, `driver_ratings`, `v_tat`, `c_tat`, plus three boolean outcome flags.

This four-step order matters: dimensions and facts are only defined *after* the grain is locked in. If the grain had been "one row per booking per status-change event" instead, for example, almost every dimension and fact below would need to change.

## 3. Key design decisions

### 3.1 Surrogate keys vs. "smart" keys

Most dimensions use a Postgres `SERIAL` **surrogate key** — an arbitrary, meaningless integer with no relationship to the business data (`vehicle_type_key`, `payment_method_key`, `booking_status_key`, `location_key`, `reason_key`). This is the standard Kimball recommendation: surrogate keys are stable even if the underlying business value changes, and they're cheap to join on.

`dim_date` and `dim_time` break this pattern deliberately and use a **smart key** instead:

```sql
date_key INT PRIMARY KEY   -- e.g. 20240115 (yyyymmdd)
time_key INT PRIMARY KEY   -- e.g. 1430 for 14:30
```

This is a common, intentional exception for date/time dimensions specifically, because:
- The key can be **computed directly from the source data** (`TO_CHAR("Date", 'YYYYMMDD')::INT`) without needing a lookup join during fact population — see `10_pop_fact.sql`, which computes `date_key` inline rather than joining to `dim_date`.
- It's human-readable in ad-hoc queries (`WHERE date_key BETWEEN 20240101 AND 20240131` is legible; a meaningless serial integer wouldn't be).

The tradeoff: if the date/time format or granularity ever needs to change, the key format is now baked into every fact row, whereas a surrogate key would have been insulated from that.

### 3.2 Degenerate dimensions

`booking_id` and `customer_id` live directly as columns on `fact_bookings`, not in their own dimension tables. `booking_id` in particular is called out explicitly as one in `08_fact_booking.sql`:

```sql
booking_id  TEXT PRIMARY KEY,   -- degenerate dimension
customer_id TEXT,               -- degenerate dimension
```

A **degenerate dimension** is an identifier that has no attributes worth modeling beyond the ID itself. `booking_id` can't be pulled into its own dimension anyway — it's the grain of the fact table, so a "dimension" of it would just be a 1:1 copy of the fact table. `customer_id` is treated the same way here because no customer *attributes* (name, signup date, tier, etc.) exist in the source data yet — if they did, a proper `dim_customer` would be worth splitting out.

### 3.3 Role-playing dimension: `dim_location`

Rather than creating `dim_pickup_location` and `dim_drop_location` as two separate tables, there's a single `dim_location` table referenced twice:

```sql
pickup_location_key INT REFERENCES dim_location(location_key),
drop_location_key   INT REFERENCES dim_location(location_key),
```

This is a **role-playing dimension** — the same dimension "plays" two different roles in the fact table. It's the correct modeling choice here because a location like "Connaught Place" is the *same real-world entity* whether it's a pickup or a drop point, and it can appear on both sides across different bookings. Splitting it into two tables would duplicate every location and make "which locations get used for both pickup and drop" impossible to answer with a simple query. The cost: every query using both roles (like `09_location.sql`) has to alias `dim_location` twice and join it twice, which is slightly more verbose but standard practice for this pattern.

### 3.4 Flags instead of a junk dimension

`canceled_by_customer_flag`, `canceled_by_driver_flag`, and `incomplete_rides_flag` are plain booleans on the fact table, derived at load time:

```sql
b."Canceled_Rides_by_Customer" IS NOT NULL,
b."Canceled_Rides_by_Driver" IS NOT NULL,
b."Incomplete_Rides" IS NOT NULL
```

An alternative design would bundle these three low-cardinality flags into a single **junk dimension** (a dimension that exists purely to hold combinations of unrelated flags, keeping the fact table narrower). That wasn't done here, most likely because three booleans don't meaningfully bloat the fact table's width, and keeping them inline makes filtering (`WHERE incomplete_rides_flag`) simpler than joining out to a junk dimension first. This is a reasonable choice at this scale; it would be worth revisiting if many more categorical flags were added later.

### 3.5 No slowly changing dimension (SCD) handling

Every dimension table is populated with a plain "insert if not already present" pattern:

```sql
INSERT INTO dim_vehicle_type (vehicle_type)
SELECT DISTINCT "Vehicle_Type" FROM booking WHERE "Vehicle_Type" IS NOT NULL;
```

(relying on the `UNIQUE` constraint on the business column to silently reject re-inserts of values that already exist — except `dim_date`, which explicitly uses `ON CONFLICT (date_key) DO NOTHING`).

This is effectively **SCD Type 0** (dimension values never change once inserted) or, generously, **Type 1** (no history kept at all). There's no `valid_from`/`valid_to`, no versioning, no tracking of "this location was renamed" or "this cancellation reason's category changed." For this dataset that's a fine choice — vehicle types, payment methods, and location names aren't expected to change meaning over time — but it's worth naming explicitly, because if a dimension's *meaning* ever needs to change while preserving historical accuracy (e.g. reclassifying which `reason_type` a cancellation reason belongs to), this design will overwrite forward rather than preserve the old association.

### 3.6 Additive vs. non-additive measures

Not all columns on `fact_bookings` behave the same way when aggregated — this matters for anyone writing queries against it (see the `sql/` folder):

| Measure | Behavior | Why |
|---|---|---|
| `booking_value` | Fully additive | Summing fares across any dimension combination is meaningful (total revenue) |
| `ride_distance` | Fully additive | Summing distance across trips is meaningful |
| `v_tat`, `c_tat` | Semi-additive | Can be averaged meaningfully; summing turnaround time across many bookings isn't a meaningful number |
| `customer_rating`, `driver_ratings` | Non-additive | Only averages (or distributions) make sense — see `07_rating.sql`'s use of `AVG()` and bucketed histograms, never `SUM()` |

This is why every analytics query in `sql/` uses `AVG()` for ratings and TAT, but `SUM()` for `booking_value` and `ride_distance` — that's not a style choice, it's what the measures' additivity allows.

## 4. Two-layer architecture: raw vs. modeled

```
Bookings.csv
    │  incremental.py  (idempotent load, keyed on Booking_ID)
    ▼
booking / bookings          <- raw layer: 1:1 copy of source, denormalized
    │  09_pop_dims.sql       (extract distinct values → dimensions)
    │  10_pop_fact.sql       (lookup keys → build fact rows)
    ▼
fact_bookings + dim_*        <- modeled layer: star schema
    │
    ▼
tests/data_quality_test.sql  <- validate the model before trusting it
    │
    ▼
sql/01–10.sql                <- business-question queries against the model
```

The raw layer exists so the *source of truth* is always just a faithful copy of the CSV — easy to re-load, easy to debug against. The modeled layer exists so *analytics* has something efficient and consistent to query. Keeping them separate means a modeling mistake never corrupts the raw data, and the star schema can be rebuilt from scratch at any time by re-running `09_pop_dims.sql` → `10_pop_fact.sql` against the untouched raw table.

## 5. Build order is not arbitrary

The `model/` folder's numeric prefixes encode a hard dependency order, driven directly by the foreign keys in `08_fact_booking.sql`:

1. **`01`–`07`**: every dimension table, created *before* the fact table, because `fact_bookings` has `REFERENCES` pointing at all seven of them. Postgres will refuse to create the fact table first.
2. **`08`**: the fact table, referencing all seven dimensions.
3. **`09_pop_dims.sql`**: dimensions must be *populated* before the fact table can be populated, because...
4. **`10_pop_fact.sql`**: ...every row here does a `LEFT JOIN` against each dimension to translate raw text (`"Vehicle_Type"`) into a surrogate key (`vehicle_type_key`). If a dimension were empty, every one of these lookups would return `NULL` — which is exactly what `data_quality_test.sql` Test 3 (unexpected NULLs) and Test 5 (dimension completeness) are designed to catch.

## 6. A gap worth knowing about: fact-load idempotency

The raw layer (`incremental.py`) is explicitly designed to be safely re-run — it upserts with `ON CONFLICT (Booking_ID) DO NOTHING`.

**`10_pop_fact.sql` does not have the same protection.** It's a plain `INSERT INTO fact_bookings (...) SELECT ... FROM booking b ...` with no `ON CONFLICT` clause. Since `booking_id` is the fact table's primary key:

- Running `10_pop_fact.sql` a second time against the *same* raw data will fail outright with a primary key violation.
- Running it after `incremental.py` has added *new* rows to the raw table will also fail, because it re-selects **every** row in `booking`, including ones already in `fact_bookings` — not just the new ones.

If the intent is to re-run the whole pipeline incrementally (matching how the raw layer already works), `10_pop_fact.sql` would need either:
```sql
... ON CONFLICT (booking_id) DO NOTHING;
```
or a `WHERE b."Booking_ID" NOT IN (SELECT booking_id FROM fact_bookings)` filter before the join. Right now, the fact/dimension layer is really a **full rebuild** script, not an incremental one — worth keeping in mind before wiring it into a recurring job.

## 7. Referential integrity strategy

All eight foreign keys on `fact_bookings` use `ON UPDATE NO ACTION / ON DELETE NO ACTION` (the Postgres default when unspecified). Practically: **Postgres will block** deleting or renaming a dimension row (e.g. a `location_name`) if any fact row still references it. Combined with the insert-only dimension population pattern in §3.5, this makes the model very safe against accidental data loss, at the cost of needing a deliberate cleanup step if a dimension value genuinely needs to be retired.

## 8. Summary: what each layer is for

| Layer | Files | Role |
|---|---|---|
| Ingestion | `scripts/incremental.py`, `utils/logger.py` | Get the CSV into Postgres, idempotently, with an audit trail |
| Schema (DDL) | `model/01`–`08` | Define the star schema's structure and constraints |
| Transform | `model/09_pop_dims.sql`, `model/10_pop_fact.sql` | Populate the model from the raw layer (currently a full rebuild — see §6) |
| Validation | `tests/data_quality_test.sql` | Confirm the model is trustworthy before anyone queries it |
| Consumption | `sql/01`–`10` | The actual business questions the model exists to answer |
| Documentation | `docs/*.md` | This file plus `model.md` (structure), `incremental.md` (loader), `data_quality.md` (tests) |