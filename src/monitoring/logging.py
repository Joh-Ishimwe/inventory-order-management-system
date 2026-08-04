"""Structured logging.

Logs go out as one JSON object per line, not free-form text. That makes them
searchable later ("show me every failure for order 41") instead of something
a human has to read line by line.
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone

from src.utils.paths import ensure_parent_dir, project_path

_CONFIGURED = False


class JsonFormatter(logging.Formatter):
    """Renders each record as a single line of JSON."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Anything passed as extra={"context": {...}} rides along, so a log
        # line can carry the order id or file name it relates to.
        context = getattr(record, "context", None)
        if isinstance(context, dict):
            payload.update(context)
        if record.exc_info:
            payload["error_type"] = record.exc_info[0].__name__
            payload["error"] = str(record.exc_info[1])
        return json.dumps(payload, default=str)


class ConsoleFormatter(logging.Formatter):
    """Renders each record as one short line for a human watching it live.

    The file gets full JSON for later searching; nobody watching a build
    happen needs a timestamp and a logger name on every line, they need to
    see what passed and what failed.
    """

    # Plain ASCII, not unicode symbols: Windows consoles default to cp1252,
    # which cannot encode most of them, and that crashes the handler mid-run.
    _MARKERS = {"ERROR": "[FAIL]", "WARNING": "[WARN]", "INFO": "[ OK ]"}

    def format(self, record: logging.LogRecord) -> str:
        marker = self._MARKERS.get(record.levelname, "[....]")
        line = f"{marker} {record.getMessage()}"

        context = getattr(record, "context", None)
        if isinstance(context, dict) and context:
            details = ", ".join(f"{k}={v}" for k, v in context.items())
            line = f"{line} ({details})"

        if record.exc_info:
            line = f"{line} -- {record.exc_info[0].__name__}: {record.exc_info[1]}"

        return line


def setup_logging(level: str = "INFO", log_file: str = "logs/pipeline.log") -> None:
    """Send a short human line to the console and full JSON to a file."""
    global _CONFIGURED
    if _CONFIGURED:
        return

    path = ensure_parent_dir(project_path(log_file))

    root = logging.getLogger()
    root.setLevel(level.upper())
    root.handlers.clear()

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(ConsoleFormatter())
    root.addHandler(console)

    file_handler = logging.FileHandler(path, encoding="utf-8")
    file_handler.setFormatter(JsonFormatter())
    root.addHandler(file_handler)

    # The driver logs its own connection/plugin chatter at INFO -- noise
    # nobody has ever grepped the log file for. Raising just this logger's
    # level drops it everywhere, without touching what the rest of the
    # app logs at INFO.
    logging.getLogger("mysql.connector").setLevel(logging.WARNING)

    _CONFIGURED = True


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
