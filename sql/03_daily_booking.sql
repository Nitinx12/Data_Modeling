-- =====================================================================
-- Q3: Daily booking volume trend
-- Business question: How does booking volume change day over day?
-- Are there spikes (promotions, weekends) or dips (data issues, holidays)?
-- =====================================================================
SELECT 
    d.full_date,
    d.day_of_week,
    d.is_weekend,
    COUNT(*) AS total_bookings,
    SUM(f.booking_value) AS total_booking_value,
    ROUND(AVG(f.booking_value), 2) AS avg_booking_value
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, d.day_of_week, d.is_weekend
ORDER BY d.full_date;

-- =====================================================================
-- Q3b: Day-over-day change in booking volume
-- Flags days where booking count jumped or dropped sharply vs prior day
-- =====================================================================
SELECT 
    d.full_date,
    COUNT(*) AS total_bookings,
    LAG(COUNT(*)) OVER (ORDER BY d.full_date) AS prev_day_bookings,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY d.full_date)) 
        / NULLIF(LAG(COUNT(*)) OVER (ORDER BY d.full_date), 0), 2
    ) AS pct_change_vs_prev_day
FROM fact_bookings f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date
ORDER BY d.full_date;