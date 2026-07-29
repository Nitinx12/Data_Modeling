
```
UBER
├─ .python-version
├─ docker
│  ├─ .dockerignore
│  ├─ compose.yml
│  ├─ Dockerfile
│  └─ Entrypoint.sh
├─ docs
│  ├─ architecture.md
│  ├─ data_quality.md
│  ├─ incremental.md
│  └─ model.md
├─ LICENSE
├─ main.py
├─ model
│  ├─ 01_dim_date.sql
│  ├─ 02_dim_time.sql
│  ├─ 03_dim_vechicle_type.sql
│  ├─ 04_dim_payment_method.sql
│  ├─ 05_dim_booking_status.sql
│  ├─ 06_dim_location.sql
│  ├─ 07_dim_cancellation_reason.sql
│  ├─ 08_fact_booking.sql
│  ├─ 09_pop_dims.sql
│  └─ 10_pop_fact.sql
├─ ps1
│  └─ pipeline.ps1
├─ pyproject.toml
├─ README.md
├─ scripts
│  ├─ data_quality_checks.py
│  └─ incremental.py
├─ sql
│  ├─ 01_booking_status_distribution.sql
│  ├─ 02_booking_revenue.sql
│  ├─ 03_daily_booking.sql
│  ├─ 04_turnaround_time.sql
│  ├─ 05_payment_method.sql
│  ├─ 06_incomplete_ride.sql
│  ├─ 07_rating.sql
│  ├─ 08_day_of_week.sql
│  ├─ 09_location.sql
│  └─ 10_cancellation_risk.sql
├─ tests
│  └─ data_quality_test.sql
├─ utils
│  ├─ db.py
│  └─ logger.py
└─ uv.lock

```