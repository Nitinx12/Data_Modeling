CREATE TABLE dim_payment_method (
    payment_method_key SERIAL PRIMARY KEY,
    payment_method     TEXT UNIQUE NOT NULL
);