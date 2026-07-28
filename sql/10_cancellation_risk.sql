-- =====================================================================
-- Q10: Cancellation risk by vehicle type + payment method + day type
-- =====================================================================
WITH risk_segments AS (
    SELECT 
        vt.vehicle_type,
        pm.payment_method,
        CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        COUNT(*) AS total_bookings,
        SUM(CASE WHEN f.canceled_by_customer_flag THEN 1 ELSE 0 END) AS canceled_by_customer,
        SUM(CASE WHEN f.canceled_by_driver_flag THEN 1 ELSE 0 END) AS canceled_by_driver
    FROM fact_bookings f
    JOIN dim_vehicle_type vt ON vt.vehicle_type_key = f.vehicle_type_key
    JOIN dim_payment_method pm ON pm.payment_method_key = f.payment_method_key
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY vt.vehicle_type, pm.payment_method, day_type
)
SELECT 
    vehicle_type,
    payment_method,
    day_type,
    total_bookings,
    canceled_by_customer,
    canceled_by_driver,
    ROUND(100.0 * (canceled_by_customer + canceled_by_driver) / total_bookings, 2) AS total_cancel_pct
FROM risk_segments
WHERE total_bookings >= 20   -- filter out tiny segments with unreliable percentages
ORDER BY total_cancel_pct DESC
LIMIT 15;