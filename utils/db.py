"""
utils/db.py
============
Shared Postgres connection helper, so every script in this project
(incremental loader, dimension/fact population, quality checks,
orchestrator) reads the same .env variables the same way, instead of
each one re-implementing this.

Usage:
    from utils.db import get_engine
    engine = get_engine()
"""

import os
from sqlalchemy import create_engine
from dotenv import load_dotenv


def get_engine():
    load_dotenv()

    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    database = os.getenv("POSTGRES_DATABASE", "postgres")
    user = os.getenv("POSTGRES_USERNAME", "postgres")
    password = os.getenv("POSTGRES_PASSWORD", "")

    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"
    return create_engine(url)