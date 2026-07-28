-- =====================================================================
-- Q6: Incomplete ride rate and breakdown by reason
-- Business question: How often do rides start but not complete, and
-- what are the most common reasons? This points to where operational
-- fixes (driver training, vehicle maintenance, app issues, etc.)
-- would have the most impact.
-- =====================================================================

-- Overall incomplete rate
SELECT 
    COUNT(*) AS total_bookings,
    SUM(CASE WHEN incomplete_rides_flag THEN 1 ELSE 0 END) AS total_incomplete,
    ROUND(100.0 * SUM(CASE WHEN incomplete_rides_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_incomplete
FROM fact_bookings;

-- Top reasons behind incomplete rides
SELECT 
    cr.reason,
    COUNT(*) AS total_incomplete_bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_incomplete
FROM fact_bookings f
JOIN dim_cancellation_reason cr ON cr.reason_key = f.incomplete_reason_key
WHERE f.incomplete_rides_flag = TRUE
GROUP BY cr.reason
ORDER BY total_incomplete_bookings DESC;

-- =====================================================================
-- Q6b: Incomplete rate by vehicle type
-- =====================================================================
SELECT 
    vt.vehicle_type,
    COUNT(*) AS total_bookings,
    SUM(CASE WHEN f.incomplete_rides_flag THEN 1 ELSE 0 END) AS incomplete_bookings,
    ROUND(100.0 * SUM(CASE WHEN f.incomplete_rides_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_incomplete
FROM fact_bookings f
JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
GROUP BY vt.vehicle_type
ORDER BY pct_incomplete DESC;