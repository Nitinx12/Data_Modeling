-- =====================================================================
-- Q5: Payment method usage and average booking value
-- Business question: Which payment method dominates usage, and is
-- there a meaningful difference in average booking value across
-- payment methods? (e.g. do card users spend more per ride than
-- cash users?)
-- =====================================================================
SELECT 
    pm.payment_method,
    COUNT(*) AS total_bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_bookings,
    SUM(f.booking_value) AS total_booking_value,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_payment_method pm ON pm.payment_method_key = f.payment_method_key
WHERE f.booking_value IS NOT NULL
GROUP BY pm.payment_method
ORDER BY total_bookings DESC;

-- =====================================================================
-- Q5b: Payment method breakdown by vehicle type
-- Reveals whether higher-end vehicle types have different payment
-- behavior than budget/economy vehicle types
-- =====================================================================
SELECT 
    vt.vehicle_type,
    pm.payment_method,
    COUNT(*) AS total_bookings,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
JOIN dim_payment_method pm ON pm.payment_method_key = f.payment_method_key
GROUP BY vt.vehicle_type, pm.payment_method
ORDER BY vt.vehicle_type, total_bookings DESC;