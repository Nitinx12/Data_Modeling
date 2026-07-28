INSERT INTO dim_vehicle_type (vehicle_type)
SELECT DISTINCT "Vehicle_Type" FROM booking WHERE "Vehicle_Type" IS NOT NULL;

INSERT INTO dim_payment_method (payment_method)
SELECT DISTINCT "Payment_Method" FROM booking WHERE "Payment_Method" IS NOT NULL;

INSERT INTO dim_booking_status (booking_status)
SELECT DISTINCT "Booking_Status" FROM booking WHERE "Booking_Status" IS NOT NULL;

INSERT INTO dim_location (location_name)
SELECT DISTINCT loc FROM (
    SELECT "Pickup_Location" AS loc FROM booking
    UNION
    SELECT "Drop_Location" AS loc FROM booking
) x WHERE loc IS NOT NULL;

INSERT INTO dim_cancellation_reason (reason)
SELECT DISTINCT "Incomplete_Rides_Reason" FROM booking WHERE "Incomplete_Rides_Reason" IS NOT NULL;

INSERT INTO dim_date (date_key, full_date, day, month, month_name, quarter, year, day_of_week, is_weekend)
SELECT DISTINCT ON (TO_CHAR("Date", 'YYYYMMDD')::INT)
    TO_CHAR("Date", 'YYYYMMDD')::INT AS date_key,
    "Date"::DATE AS full_date,
    EXTRACT(DAY FROM "Date"),
    EXTRACT(MONTH FROM "Date"),
    TO_CHAR("Date", 'Month'),
    EXTRACT(QUARTER FROM "Date"),
    EXTRACT(YEAR FROM "Date"),
    TO_CHAR("Date", 'Day'),
    EXTRACT(ISODOW FROM "Date") IN (6,7)
FROM booking
WHERE "Date" IS NOT NULL
ORDER BY TO_CHAR("Date", 'YYYYMMDD')::INT
ON CONFLICT (date_key) DO NOTHING;