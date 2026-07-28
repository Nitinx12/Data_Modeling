-- =====================================================================
-- Q9: Top pickup-to-drop location pairs by trip volume
-- Business question: Which routes are most frequently traveled?
-- This helps with driver allocation, hotspot identification, and
-- understanding whether demand is concentrated on a few key corridors
-- or spread evenly across many origin-destination combinations.
-- =====================================================================
SELECT 
    pl.location_name AS pickup_location,
    dl.location_name AS drop_location,
    COUNT(*) AS total_trips,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value,
    ROUND(AVG(f.ride_distance), 2) AS avg_ride_distance
FROM fact_bookings f
JOIN dim_location pl ON pl.location_key = f.pickup_location_key
JOIN dim_location dl ON dl.location_key = f.drop_location_key
GROUP BY pl.location_name, dl.location_name
ORDER BY total_trips DESC
LIMIT 15;

-- =====================================================================
-- Q9b: Top pickup locations by demand (regardless of destination)
-- Shows overall geographic demand concentration — useful for driver
-- positioning and identifying high-demand zones independent of route
-- =====================================================================
SELECT 
    pl.location_name AS pickup_location,
    COUNT(*) AS total_trips,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total_trips
FROM fact_bookings f
JOIN dim_location pl ON pl.location_key = f.pickup_location_key
GROUP BY pl.location_name
ORDER BY total_trips DESC
LIMIT 10;