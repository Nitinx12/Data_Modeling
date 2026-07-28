CREATE TABLE fact_bookings (
    booking_id                  TEXT PRIMARY KEY,   -- degenerate dimension
    customer_id                 TEXT,               -- degenerate dimension
    date_key                    INT REFERENCES dim_date(date_key),
    time_key                    INT REFERENCES dim_time(time_key),
    vehicle_type_key            INT REFERENCES dim_vehicle_type(vehicle_type_key),
    payment_method_key          INT REFERENCES dim_payment_method(payment_method_key),
    booking_status_key          INT REFERENCES dim_booking_status(booking_status_key),
    pickup_location_key         INT REFERENCES dim_location(location_key),
    drop_location_key           INT REFERENCES dim_location(location_key),
    incomplete_reason_key       INT REFERENCES dim_cancellation_reason(reason_key),

    -- measures
    booking_value               NUMERIC(10,2),
    ride_distance               NUMERIC(10,2),
    customer_rating             NUMERIC(3,2),
    driver_ratings              NUMERIC(3,2),
    v_tat                       NUMERIC(10,2),
    c_tat                       NUMERIC(10,2),
    canceled_by_customer_flag   BOOLEAN,
    canceled_by_driver_flag     BOOLEAN,
    incomplete_rides_flag       BOOLEAN
);