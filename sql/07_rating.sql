-- =====================================================================
-- Q7: Customer rating vs driver rating, overall and by vehicle type
-- Business question: Are customer satisfaction and driver satisfaction
-- aligned? Does any vehicle type show a notable gap between the two,
-- which could point to service quality issues specific to that segment?
-- =====================================================================

-- Overall averages
SELECT 
    ROUND(AVG(customer_rating), 2) AS avg_customer_rating,
    ROUND(AVG(driver_ratings), 2) AS avg_driver_rating,
    ROUND(AVG(customer_rating) - AVG(driver_ratings), 2) AS rating_gap
FROM fact_bookings
WHERE customer_rating IS NOT NULL AND driver_ratings IS NOT NULL;

-- By vehicle type
SELECT 
    vt.vehicle_type,
    COUNT(*) AS total_bookings,
    ROUND(AVG(f.customer_rating), 2) AS avg_customer_rating,
    ROUND(AVG(f.driver_ratings), 2) AS avg_driver_rating,
    ROUND(AVG(f.customer_rating) - AVG(f.driver_ratings), 2) AS rating_gap
FROM fact_bookings f
JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
WHERE f.customer_rating IS NOT NULL AND f.driver_ratings IS NOT NULL
GROUP BY vt.vehicle_type
ORDER BY rating_gap DESC;

-- =====================================================================
-- Q7b: Rating distribution (histogram-style)
-- Checks whether ratings are meaningfully spread or clustered near the top
-- (common in ride-hailing data where most ratings skew 4-5)
-- =====================================================================
SELECT 
    ROUND(customer_rating) AS rating_bucket,
    COUNT(*) AS total_bookings
FROM fact_bookings
WHERE customer_rating IS NOT NULL
GROUP BY rating_bucket
ORDER BY rating_bucket;