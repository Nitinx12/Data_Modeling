CREATE TABLE dim_vehicle_type (
    vehicle_type_key SERIAL PRIMARY KEY,
    vehicle_type     TEXT UNIQUE NOT NULL
);