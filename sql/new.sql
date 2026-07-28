SELECT *
FROM(
    SELECT
        *,
        ROW_NUMBER() OVER(
            PARTITION BY "Booking_ID"
            ORDER BY "Date"
        ) AS rnk
    FROM booking
) AS X
WHERE X.rnk > 1
