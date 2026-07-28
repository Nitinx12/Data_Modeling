-- =====================================================================
-- Q4: Ride distance and TAT (turnaround time) by vehicle type
-- Business question: Do certain vehicle types cover longer distances?
-- Do they also take longer for the vehicle to arrive (V_TAT) or for
-- the customer-side process (C_TAT)? Useful for spotting operational
-- bottlenecks tied to specific vehicle categories.
-- =====================================================================
SELECT 
    vt.vehicle_type,
    COUNT(*) AS total_bookings,
    ROUND(AVG(f.ride_distance), 2) AS avg_ride_distance,
    ROUND(MIN(f.ride_distance), 2) AS min_ride_distance,
    ROUND(MAX(f.ride_distance), 2) AS max_ride_distance,
    ROUND(AVG(f.v_tat), 2) AS avg_vehicle_tat,
    ROUND(AVG(f.c_tat), 2) AS avg_customer_tat
FROM fact_bookings f
JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
WHERE f.ride_distance IS NOT NULL
GROUP BY vt.vehicle_type
ORDER BY avg_ride_distance DESC;

-- =====================================================================
-- Q4b: Correlation check — does higher distance mean higher TAT?
-- Buckets rides into distance ranges to see if TAT scales sensibly
-- =====================================================================
SELECT 
    CASE 
        WHEN ride_distance < 5 THEN '0-5 km'
        WHEN ride_distance < 10 THEN '5-10 km'
        WHEN ride_distance < 20 THEN '10-20 km'
        ELSE '20+ km'
    END AS distance_bucket,
    COUNT(*) AS total_bookings,
    ROUND(AVG(v_tat), 2) AS avg_vehicle_tat,
    ROUND(AVG(c_tat), 2) AS avg_customer_tat
FROM fact_bookings
WHERE ride_distance IS NOT NULL
GROUP BY distance_bucket
ORDER BY MIN(ride_distance);