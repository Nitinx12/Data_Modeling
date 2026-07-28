CREATE TABLE dim_cancellation_reason (
    reason_key SERIAL PRIMARY KEY,
    reason     TEXT UNIQUE NOT NULL,
    reason_type TEXT   -- 'Customer Cancel' / 'Driver Cancel' / 'Incomplete'
);