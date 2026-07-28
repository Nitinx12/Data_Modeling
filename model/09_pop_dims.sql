-- =====================================================================
-- Populate all dimension tables from distinct values in the raw
-- `booking` table.
--
-- Made safe to re-run: every INSERT now uses ON CONFLICT DO NOTHING
-- against each dimension's UNIQUE business column, so re-running this
-- script after new rows land in `booking` only adds genuinely new
-- dimension values instead of erroring on a duplicate key violation.
-- (Previously, only the dim_date insert had this protection.)
-- =====================================================================

INSERT INTO dim_vehicle_type (vehicle_type)
SELECT DISTINCT "Vehicle_Type" FROM bookings WHERE "Vehicle_Type" IS NOT NULL
ON CONFLICT (vehicle_type) DO NOTHING;

INSERT INTO dim_payment_method (payment_method)
SELECT DISTINCT "Payment_Method" FROM bookings WHERE "Payment_Method" IS NOT NULL
ON CONFLICT (payment_method) DO NOTHING;

-- Explicit placeholder for bookings that never completed (Canceled by Driver/
-- Customer, Driver Not Found), which never had a Payment_Method recorded.
-- fact load in 10_pop_fact.sql maps NULL Payment_Method to this value so the
-- fact table never has a null payment_method_key FK.
INSERT INTO dim_payment_method (payment_method)
VALUES ('N/A - Trip Not Completed')
ON CONFLICT (payment_method) DO NOTHING;

INSERT INTO dim_booking_status (booking_status)
SELECT DISTINCT "Booking_Status" FROM bookings WHERE "Booking_Status" IS NOT NULL
ON CONFLICT (booking_status) DO NOTHING;

INSERT INTO dim_location (location_name)
SELECT DISTINCT loc FROM (
    SELECT "Pickup_Location" AS loc FROM bookings
    UNION
    SELECT "Drop_Location" AS loc FROM bookings
) x WHERE loc IS NOT NULL
ON CONFLICT (location_name) DO NOTHING;

INSERT INTO dim_cancellation_reason (reason)
SELECT DISTINCT "Incomplete_Rides_Reason" FROM bookings WHERE "Incomplete_Rides_Reason" IS NOT NULL
ON CONFLICT (reason) DO NOTHING;

-- NOTE: "Date" is stored as TEXT in the source `booking` table, so every
-- date function below needs an explicit ::DATE cast first (Postgres has no
-- to_char/extract overload that takes text directly).
INSERT INTO dim_date (date_key, full_date, day, month, month_name, quarter, year, day_of_week, is_weekend)
SELECT DISTINCT ON (TO_CHAR("Date"::DATE, 'YYYYMMDD')::INT)
    TO_CHAR("Date"::DATE, 'YYYYMMDD')::INT AS date_key,
    "Date"::DATE AS full_date,
    EXTRACT(DAY FROM "Date"::DATE),
    EXTRACT(MONTH FROM "Date"::DATE),
    TO_CHAR("Date"::DATE, 'Month'),
    EXTRACT(QUARTER FROM "Date"::DATE),
    EXTRACT(YEAR FROM "Date"::DATE),
    TO_CHAR("Date"::DATE, 'Day'),
    EXTRACT(ISODOW FROM "Date"::DATE) IN (6,7)
FROM bookings
WHERE "Date" IS NOT NULL
ORDER BY TO_CHAR("Date"::DATE, 'YYYYMMDD')::INT
ON CONFLICT (date_key) DO NOTHING;