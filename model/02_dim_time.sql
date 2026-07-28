CREATE TABLE dim_time (
    time_key   INT PRIMARY KEY,   -- e.g. 1430 for 14:30
    full_time  TIME NOT NULL,
    hour       INT,
    minute     INT,
    am_pm      TEXT
);