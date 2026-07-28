CREATE TABLE dim_booking_status (
    booking_status_key SERIAL PRIMARY KEY,
    booking_status     TEXT UNIQUE NOT NULL
);