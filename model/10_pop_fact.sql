INSERT INTO fact_bookings (
    booking_id, 
    customer_id, 
    date_key, 
    vehicle_type_key, 
    payment_method_key,
    booking_status_key, 
    pickup_location_key, 
    drop_location_key, 
    incomplete_reason_key,
    booking_value, 
    ride_distance, 
    customer_rating, 
    driver_ratings, 
    v_tat, 
    c_tat,
    canceled_by_customer_flag, 
    canceled_by_driver_flag, 
    incomplete_rides_flag
)
SELECT
    b."Booking_ID",
    b."Customer_ID",
    TO_CHAR(b."Date", 'YYYYMMDD')::INT,
    vt.vehicle_type_key,
    pm.payment_method_key,
    bs.booking_status_key,
    pl.location_key,
    dl.location_key,
    cr.reason_key,
    b."Booking_Value",
    b."Ride_Distance",
    b."Customer_Rating",
    b."Driver_Ratings",
    b."V_TAT",
    b."C_TAT",
    b."Canceled_Rides_by_Customer" IS NOT NULL,
    b."Canceled_Rides_by_Driver" IS NOT NULL,
    b."Incomplete_Rides" IS NOT NULL
FROM booking b
LEFT JOIN dim_vehicle_type vt ON vt.vehicle_type = b."Vehicle_Type"
LEFT JOIN dim_payment_method pm ON pm.payment_method = b."Payment_Method"
LEFT JOIN dim_booking_status bs ON bs.booking_status = b."Booking_Status"
LEFT JOIN dim_location pl ON pl.location_name = b."Pickup_Location"
LEFT JOIN dim_location dl ON dl.location_name = b."Drop_Location"
LEFT JOIN dim_cancellation_reason cr ON cr.reason = b."Incomplete_Rides_Reason";