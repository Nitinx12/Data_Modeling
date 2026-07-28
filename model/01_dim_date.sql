CREATE TABLE dim_date (
    date_key    INT PRIMARY KEY,        -- e.g. 20240115 (yyyymmdd)
    full_date   DATE NOT NULL,
    day         INT,
    month       INT,
    month_name  TEXT,
    quarter     INT,
    year        INT,
    day_of_week TEXT,
    is_weekend  BOOLEAN
);