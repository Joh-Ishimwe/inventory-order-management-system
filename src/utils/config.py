"""Configuration loading.

Settings that change per environment live in config/*.yaml.
Secrets live in .env and are never committed.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml
from dotenv import load_dotenv

from src.utils.paths import project_path


@dataclass(frozen=True)
class DatabaseConfig:
    host: str
    port: int
    database: str
    user: str
    password: str
    # Every network call gets a timeout. Without one, a hung server holds
    # the pipeline open indefinitely instead of failing so it can retry.
    connect_timeout: int


@dataclass(frozen=True)
class RetryConfig:
    max_attempts: int
    base_delay_seconds: float
    max_delay_seconds: float


@dataclass(frozen=True)
class AppConfig:
    environment: str
    database: DatabaseConfig
    retry: RetryConfig
    log_level: str
    log_file: str


def load_config(environment: str | None = None) -> AppConfig:
    load_dotenv(project_path(".env"), override=False)

    env = environment or os.getenv("APP_ENV", "dev")
    config_file = project_path("config", f"{env}.yaml")
    if not config_file.exists():
        raise FileNotFoundError(f"No config file for environment '{env}': {config_file}")

    with open(config_file, "r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}

    db = raw.get("database", {})
    retry = raw.get("retry", {})
    logging_cfg = raw.get("logging", {})

    # Credentials come from the environment, never from the YAML file,
    # so config can be committed and secrets cannot leak with it.
    return AppConfig(
        environment=env,
        database=DatabaseConfig(
            host=db.get("host", "127.0.0.1"),
            port=int(db.get("port", 3306)),
            database=db.get("database", "inventory_order_management"),
            user=os.getenv("DB_USER", "root"),
            password=os.getenv("DB_PASSWORD", ""),
            connect_timeout=int(db.get("connect_timeout_seconds", 10)),
        ),
        retry=RetryConfig(
            max_attempts=int(retry.get("max_attempts", 3)),
            base_delay_seconds=float(retry.get("base_delay_seconds", 0.5)),
            max_delay_seconds=float(retry.get("max_delay_seconds", 8.0)),
        ),
        log_level=logging_cfg.get("level", "INFO"),
        log_file=logging_cfg.get("file", "logs/pipeline.log"),
    )
