-- =====================================================================
-- TEST 1: Row count match between source and fact table
-- Expected: source_count and fact_count should be EQUAL
-- If fact_count < source_count, some rows were dropped during load
-- (likely due to a failed join or missing dimension key)
-- =====================================================================
SELECT 
    (SELECT COUNT(*) FROM booking) AS source_count,
    (SELECT COUNT(*) FROM fact_bookings) AS fact_count;


-- =====================================================================
-- TEST 2: Check for duplicate Booking_IDs in fact table
-- Expected: 0 rows returned
-- Since booking_id is our primary key / grain, duplicates mean
-- the same booking got loaded more than once
-- =====================================================================
SELECT booking_id, COUNT(*) AS cnt
FROM fact_bookings
GROUP BY booking_id
HAVING COUNT(*) > 1;


-- =====================================================================
-- TEST 3: Null foreign key check across all dimension keys
-- Expected: all columns should show 0 (or very low counts that are
-- explainable, e.g. incomplete_reason_key will be null for completed rides)
-- Non-zero unexpected nulls mean the JOIN during fact load failed
-- to match a dimension value (e.g. typo, case mismatch, trailing space)
-- =====================================================================
SELECT 
    SUM(CASE WHEN date_key IS NULL THEN 1 ELSE 0 END) AS null_date,
    SUM(CASE WHEN vehicle_type_key IS NULL THEN 1 ELSE 0 END) AS null_vehicle,
    SUM(CASE WHEN payment_method_key IS NULL THEN 1 ELSE 0 END) AS null_payment,
    SUM(CASE WHEN booking_status_key IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN pickup_location_key IS NULL THEN 1 ELSE 0 END) AS null_pickup,
    SUM(CASE WHEN drop_location_key IS NULL THEN 1 ELSE 0 END) AS null_drop
FROM fact_bookings;


-- =====================================================================
-- TEST 4: Orphaned foreign keys (fact points to a dim key that doesn't exist)
-- Expected: 0 rows for each check
-- This catches "silent" FK issues if constraints were ever disabled
-- =====================================================================
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


-- =====================================================================
-- TEST 5: Distinct value count match (dimension completeness)
-- Expected: distinct_in_source should equal rows_in_dim for each dimension
-- If dim has FEWER rows than source distinct values, some values never
-- made it into the dimension table (like our earlier dim_date issue)
-- =====================================================================
SELECT 
    (SELECT COUNT(DISTINCT "Vehicle_Type") FROM booking) AS distinct_vehicle_source,
    (SELECT COUNT(*) FROM dim_vehicle_type) AS rows_in_dim_vehicle,
    (SELECT COUNT(DISTINCT "Payment_Method") FROM booking) AS distinct_payment_source,
    (SELECT COUNT(*) FROM dim_payment_method) AS rows_in_dim_payment,
    (SELECT COUNT(DISTINCT TO_CHAR("Date",'YYYYMMDD')) FROM booking) AS distinct_date_source,
    (SELECT COUNT(*) FROM dim_date) AS rows_in_dim_date;


-- =====================================================================
-- TEST 6: Measure sanity check (no impossible negative values)
-- Expected: 0 rows — booking_value, ride_distance, TAT should never be negative
-- Negative values suggest a data type or unit conversion issue
-- =====================================================================
SELECT COUNT(*) AS invalid_measure_rows
FROM fact_bookings
WHERE booking_value < 0 
   OR ride_distance < 0 
   OR v_tat < 0 
   OR c_tat < 0;


-- =====================================================================
-- TEST 7: Rating range check
-- Expected: 0 rows — ratings should fall within a valid scale (commonly 1–5)
-- If any ratings fall outside this range, source data or casting is off
-- =====================================================================
SELECT COUNT(*) AS invalid_rating_rows
FROM fact_bookings
WHERE (customer_rating IS NOT NULL AND (customer_rating < 1 OR customer_rating > 5))
   OR (driver_ratings IS NOT NULL AND (driver_ratings < 1 OR driver_ratings > 5));


-- =====================================================================
-- TEST 8: Booking status logic consistency
-- Expected: cancellation/incomplete flags should align with booking_status
-- e.g., a booking marked "Completed" should NOT also have 
-- canceled_by_customer_flag = true
-- Any mismatches here signal a logic/ETL bug, not just data quality
-- =====================================================================
SELECT bs.booking_status, 
    SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_customer,
    SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) AS flagged_canceled_by_driver,
    SUM(CASE WHEN f.incomplete_rides_flag THEN 1 ELSE 0 END) AS flagged_incomplete
FROM fact_bookings f
JOIN dim_booking_status bs ON bs.booking_status_key = f.booking_status_key
GROUP BY bs.booking_status
ORDER BY bs.booking_status;


-- =====================================================================
-- TEST 9: Date range sanity check
-- Expected: min_date and max_date should match the known range of your
-- source data (e.g. if this is July 2024 data, confirm it doesn't span
-- into unexpected months/years due to a parsing error)
-- =====================================================================
SELECT MIN(d.full_date) AS min_date, MAX(d.full_date) AS max_date, COUNT(DISTINCT d.full_date) AS distinct_days
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key;


-- =====================================================================
-- TEST 10: Pickup/Drop location referential check
-- Expected: 0 rows — every pickup and drop location key in fact should 
-- resolve to a real row in dim_location (role-playing dimension check,
-- since we reuse the same dim table for two different fact columns)
-- =====================================================================
SELECT 'pickup' AS role, COUNT(*) AS unmatched
FROM fact_bookings f
LEFT JOIN dim_location l ON l.location_key = f.pickup_location_key
WHERE f.pickup_location_key IS NOT NULL AND l.location_key IS NULL

UNION ALL

SELECT 'drop', COUNT(*)
FROM fact_bookings f
LEFT JOIN dim_location l ON l.location_key = f.drop_location_key
WHERE f.drop_location_key IS NOT NULL AND l.location_key IS NULL;