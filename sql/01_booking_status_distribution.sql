-- =====================================================================
-- Q1: Overall booking status distribution + cancellation/incomplete rates
-- Business question: Out of all bookings, how many completed successfully
-- vs got cancelled (by customer/driver) vs remained incomplete?
-- =====================================================================
SELECT 
    bs.booking_status,
    COUNT(*) AS total_bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM fact_bookings f
JOIN dim_booking_status bs ON bs.booking_status_key = f.booking_status_key
GROUP BY bs.booking_status
ORDER BY total_bookings DESC;

-- Cancellation and incompletion rate as a %, independent of booking_status labels
SELECT
    COUNT(*) AS total_bookings,
    SUM(CASE WHEN canceled_by_customer_flag THEN 1 ELSE 0 END) AS canceled_by_customer,
    SUM(CASE WHEN canceled_by_driver_flag THEN 1 ELSE 0 END) AS canceled_by_driver,
    SUM(CASE WHEN incomplete_rides_flag THEN 1 ELSE 0 END) AS incomplete_rides,
    ROUND(100.0 * SUM(CASE WHEN canceled_by_customer_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_customer,
    ROUND(100.0 * SUM(CASE WHEN canceled_by_driver_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_canceled_by_driver,
    ROUND(100.0 * SUM(CASE WHEN incomplete_rides_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_incomplete
FROM fact_bookings;