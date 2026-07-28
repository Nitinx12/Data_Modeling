CREATE TABLE dim_location (
    location_key  SERIAL PRIMARY KEY,
    location_name TEXT UNIQUE NOT NULL
);