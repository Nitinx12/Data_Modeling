-- =====================================================================
-- Q8: Day-of-week pattern in volume and cancellations
-- Business question: Do weekends see higher demand than weekdays?
-- Does the cancellation rate (by customer or driver) shift on
-- weekends vs weekdays — useful for staffing and incentive planning.
-- =====================================================================
SELECT 
    d.day_of_week,
    d.is_weekend,
    COUNT(*) AS total_bookings,
    SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) AS canceled_by_customer,
    SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) AS canceled_by_driver,
    ROUND(100.0 * SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_customer,
    ROUND(100.0 * SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_driver,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.day_of_week, d.is_weekend
ORDER BY total_bookings DESC;

-- =====================================================================
-- Q8b: Weekend vs weekday rollup
-- Aggregates all weekend days together vs all weekday days together
-- for a cleaner high-level comparison
-- =====================================================================
SELECT 
    CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*) AS total_bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_bookings,
    ROUND(100.0 * SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_customer,
    ROUND(100.0 * SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_driver,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY day_type;