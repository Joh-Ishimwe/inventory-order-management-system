"""MySQL access layer.

Everything that talks to the database goes through here, so timeouts,
retries and error handling are written once rather than in every pipeline.
"""
from __future__ import annotations

import re
import time
from typing import Any, Callable, Iterable, Sequence

import mysql.connector
from mysql.connector import Error as MySQLError

from src.monitoring.logging import get_logger
from src.utils.config import AppConfig
from src.utils.constants import PERMANENT_MYSQL_ERRORS, TRANSIENT_MYSQL_ERRORS
from src.utils.paths import project_path

logger = get_logger(__name__)


class PermanentDatabaseError(Exception):
    """Something retrying will not fix: bad SQL, bad input, a rule said no."""


class TransientDatabaseError(Exception):
    """Something that may well work on the next attempt."""


def classify(error: MySQLError) -> Exception:
    """Decide whether an error is worth retrying.

    Retrying a permanent error just delays the real report and can repeat a
    side effect. Failing fast on a transient one throws away a run that
    would have succeeded a second later. So the two are separated here.
    """
    code = getattr(error, "errno", None)
    if code in TRANSIENT_MYSQL_ERRORS:
        return TransientDatabaseError(f"[{code}] {error}")
    if code in PERMANENT_MYSQL_ERRORS:
        return PermanentDatabaseError(f"[{code}] {error}")
    # Unknown codes are treated as permanent. Better to surface something
    # unexpected than to hammer the server over and over.
    return PermanentDatabaseError(f"[{code}] {error}")


def split_sql_script(script: str) -> list[str]:
    """Split a .sql file into statements, honouring DELIMITER.

    DELIMITER is a command the mysql command-line tool understands, not
    real SQL, so a driver never sees it. Stored procedures need it, because
    their bodies contain semicolons. This handles it so the same .sql files
    work from the terminal and from Python.

    Limitation: comment lines are stripped before parsing, so a string
    literal containing a line that starts with "--" would lose that line.
    None of the project's SQL does that, but a full parser would be needed
    for arbitrary input.
    """
    statements: list[str] = []
    delimiter = ";"
    buffer: list[str] = []

    for raw_line in script.splitlines():
        stripped = raw_line.strip()

        if not stripped or stripped.startswith("--"):
            continue

        match = re.match(r"^DELIMITER\s+(\S+)$", stripped, re.IGNORECASE)
        if match:
            # Flush anything pending before the delimiter changes.
            pending = "\n".join(buffer).strip()
            if pending:
                statements.append(pending)
            buffer = []
            delimiter = match.group(1)
            continue

        if stripped.endswith(delimiter):
            buffer.append(stripped[: -len(delimiter)])
            statement = "\n".join(buffer).strip()
            if statement:
                statements.append(statement)
            buffer = []
        else:
            buffer.append(raw_line)

    leftover = "\n".join(buffer).strip()
    if leftover:
        statements.append(leftover)
    return statements


class MySQLClient:
    """Thin wrapper that adds timeouts, retries and structured logging."""

    def __init__(self, config: AppConfig, use_database: bool = True) -> None:
        self._config = config
        self._use_database = use_database
        self._connection = None

    # -- connection handling -------------------------------------------------

    def connect(self) -> None:
        db = self._config.database
        params: dict[str, Any] = {
            "host": db.host,
            "port": db.port,
            "user": db.user,
            "password": db.password,
            "connection_timeout": db.connect_timeout,
            # Off, so a transaction is only committed when we say so.
            "autocommit": False,
        }
        if self._use_database:
            params["database"] = db.database

        def _open():
            return mysql.connector.connect(**params)

        self._connection = self._with_retries(_open, "connect")
        logger.info("connected", extra={"context": {"host": db.host, "port": db.port}})

    def close(self) -> None:
        if self._connection is not None and self._connection.is_connected():
            self._connection.close()
            logger.info("connection closed")

    def __enter__(self) -> "MySQLClient":
        self.connect()
        return self

    def __exit__(self, *_exc) -> None:
        self.close()

    # -- retry logic ---------------------------------------------------------

    def _with_retries(self, action: Callable[[], Any], label: str) -> Any:
        """Retry transient failures with exponential backoff.

        The delay doubles each time (0.5s, 1s, 2s...) rather than retrying
        instantly, which would just pile more load onto a server that is
        already struggling.
        """
        retry = self._config.retry
        delay = retry.base_delay_seconds
        last: Exception | None = None

        for attempt in range(1, retry.max_attempts + 1):
            try:
                return action()
            except MySQLError as exc:
                classified = classify(exc)
                if isinstance(classified, PermanentDatabaseError):
                    logger.error(
                        "permanent database error, not retrying",
                        extra={"context": {"operation": label, "attempt": attempt}},
                    )
                    raise classified from exc
                last = classified
                logger.warning(
                    "transient database error, will retry",
                    extra={
                        "context": {
                            "operation": label,
                            "attempt": attempt,
                            "of": retry.max_attempts,
                            "retry_in_seconds": round(delay, 2),
                            "detail": str(classified),
                        }
                    },
                )
                if attempt < retry.max_attempts:
                    time.sleep(delay)
                    delay = min(delay * 2, retry.max_delay_seconds)

        raise last or TransientDatabaseError(f"{label} failed after retries")

    # -- statements ----------------------------------------------------------

    def execute(self, sql: str, params: Sequence[Any] | None = None,
                collect: bool = False) -> list[list[Any]]:
        """Run one statement and fully drain whatever it returns.

        multi=True is required, not optional: a CALL to a procedure that
        runs PREPARE/EXECUTE internally (expect_error) makes the server
        report extra results, and the connector's single-statement path
        (cmd_query) raises "Use cmd_query_iter for statements with multiple
        queries" for that even though the SQL text itself is one statement.
        multi=True routes through cmd_query_iter instead. Rows are only
        kept when the caller asks for them.
        """
        def _run():
            collected: list[list[Any]] = []
            with self._connection.cursor(buffered=True) as cursor:
                for result_cursor in cursor.execute(sql, params or (), multi=True):
                    if result_cursor.with_rows:
                        rows = result_cursor.fetchall()
                        if collect and rows:
                            collected.append(rows)
            self._connection.commit()
            return collected

        return self._with_retries(_run, "execute")

    def call_procedure(self, name: str, args: Iterable[Any]) -> list[Any]:
        def _run():
            with self._connection.cursor() as cursor:
                result = cursor.callproc(name, list(args))
            self._connection.commit()
            return list(result)

        return self._with_retries(_run, f"call:{name}")

    def query(self, sql: str, params: Sequence[Any] | None = None) -> list[dict[str, Any]]:
        def _run():
            with self._connection.cursor(dictionary=True) as cursor:
                cursor.execute(sql, params or ())
                return cursor.fetchall()

        return self._with_retries(_run, "query")

    def run_script_file(self, relative_path: str, echo_results: bool = False) -> int:
        """Run every statement in a .sql file, in order."""
        path = project_path(relative_path)
        if not path.exists():
            raise PermanentDatabaseError(f"SQL file not found: {relative_path}")

        script = path.read_text(encoding="utf-8")
        statements = split_sql_script(script)

        for index, statement in enumerate(statements, start=1):
            try:
                output = self.execute(statement, collect=echo_results)
                # Test scripts print PASS lines; surface them rather than
                # silently swallowing the thing you ran the tests to see.
                for rows in output:
                    for row in rows:
                        logger.info(
                            "  " + " | ".join("" if c is None else str(c) for c in row)
                        )
            except Exception:
                logger.error(
                    "statement failed",
                    extra={
                        "context": {
                            "file": relative_path,
                            "statement_number": index,
                            "sql_preview": statement[:120].replace("\n", " "),
                        }
                    },
                )
                raise

        logger.info(
            "script complete",
            extra={"context": {"file": relative_path, "statements": len(statements)}},
        )
        return len(statements)
