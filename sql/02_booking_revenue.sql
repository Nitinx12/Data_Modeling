-- =====================================================================
-- Q2: Revenue and volume by vehicle type
-- Business question: Which vehicle types drive the most bookings vs
-- the most revenue? Are they the same, or does a low-volume vehicle
-- type actually generate disproportionately high value per ride?
-- =====================================================================
SELECT 
    vt.vehicle_type,
    COUNT(*) AS total_bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_bookings,
    SUM(f.booking_value) AS total_booking_value,
    ROUND(100.0 * SUM(f.booking_value) / SUM(SUM(f.booking_value)) OVER (), 2) AS pct_of_revenue,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
WHERE f.booking_value IS NOT NULL
GROUP BY vt.vehicle_type
ORDER BY total_booking_value DESC;