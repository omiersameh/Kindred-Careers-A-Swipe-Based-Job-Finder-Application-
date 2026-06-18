"""
swipe_store.py — Persistent swipe-state tracking via stdlib sqlite3.

Architecture:
  • Stores: user_id, job_id, swipe_action ('like' | 'dislike' | 'skip'), timestamp
  • DB file: swipes.db (in the backend/ working directory)
  • No new pip packages — uses Python stdlib sqlite3 exclusively.
  • swipes.db is excluded from Docker images via .dockerignore.

Selection Criteria (per spec):
  1. Identify all job_ids the active user has already swiped.
  2. Exclude those swiped jobs completely from the DB query BEFORE vector search.
  3. Run vector similarity search only on remaining unviewed jobs.
"""

import os
import sqlite3
import threading
from datetime import datetime
from typing import Set, List, Optional

# ──────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────
_DB_FILE = os.getenv("SWIPES_DB_PATH", "./swipes.db")

# Thread-local storage for SQLite connections (SQLite connections are not
# thread-safe when shared; using thread-local ensures each thread has its own).
_local = threading.local()

_SCHEMA = """
CREATE TABLE IF NOT EXISTS user_swipes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     TEXT    NOT NULL,
    job_id      TEXT    NOT NULL,
    swipe_action TEXT   NOT NULL CHECK (swipe_action IN ('like', 'dislike', 'skip')),
    swiped_at   TEXT    NOT NULL,
    UNIQUE (user_id, job_id)          -- one record per user-job pair (upsert-safe)
);

CREATE INDEX IF NOT EXISTS idx_user_swipes_user_id ON user_swipes (user_id);
"""


# ──────────────────────────────────────────────────────────────────────
# Connection management
# ──────────────────────────────────────────────────────────────────────

def _get_conn() -> sqlite3.Connection:
    """Returns a per-thread SQLite connection, creating + migrating the DB on first use."""
    if not hasattr(_local, "conn") or _local.conn is None:
        _local.conn = sqlite3.connect(_DB_FILE, check_same_thread=False)
        _local.conn.row_factory = sqlite3.Row
        _local.conn.executescript(_SCHEMA)
        _local.conn.commit()
    return _local.conn


# ──────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────

def record_swipe(user_id: str, job_id: str, action: str = "skip") -> None:
    """
    Persists a single swipe event.
    Uses INSERT OR REPLACE so swiping the same job twice (direction change) is safe.

    Args:
        user_id:  Firebase UID or any unique user identifier.
        job_id:   ChromaDB stable job ID (e.g. 'job_a1b2c3d4e5f6...').
        action:   'like', 'dislike', or 'skip'.
    """
    action = action.lower()
    if action not in ("like", "dislike", "skip"):
        action = "skip"

    conn = _get_conn()
    conn.execute(
        """
        INSERT INTO user_swipes (user_id, job_id, swipe_action, swiped_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(user_id, job_id) DO UPDATE SET
            swipe_action = excluded.swipe_action,
            swiped_at    = excluded.swiped_at
        """,
        (user_id, job_id, action, datetime.now().isoformat()),
    )
    conn.commit()


def get_swiped_ids(user_id: str) -> Set[str]:
    """
    Returns the full set of job_ids this user has already swiped (any direction).
    These are excluded from the vector similarity search before it runs.

    Args:
        user_id: Firebase UID or any unique user identifier.

    Returns:
        A set of job ID strings.
    """
    conn = _get_conn()
    rows = conn.execute(
        "SELECT job_id FROM user_swipes WHERE user_id = ?",
        (user_id,),
    ).fetchall()
    return {row["job_id"] for row in rows}


def get_swipe_count(user_id: str, since_iso: Optional[str] = None) -> int:
    """
    Returns the total number of distinct jobs served/swiped for a user.
    Used by the rate limiter to enforce the 30-jobs-per-5-hours quota.

    Args:
        user_id:    Firebase UID.
        since_iso:  ISO timestamp string — only count swipes after this point.
                    If None, counts all swipes ever for this user.

    Returns:
        Integer count of swiped job records.
    """
    conn = _get_conn()
    if since_iso:
        row = conn.execute(
            "SELECT COUNT(*) AS cnt FROM user_swipes WHERE user_id = ? AND swiped_at >= ?",
            (user_id, since_iso),
        ).fetchone()
    else:
        row = conn.execute(
            "SELECT COUNT(*) AS cnt FROM user_swipes WHERE user_id = ?",
            (user_id,),
        ).fetchone()
    return row["cnt"] if row else 0


def clear_swipes(user_id: str) -> int:
    """
    Deletes all swipe records for a specific user.
    Intended for developer testing and DB stress-testing resets.

    Args:
        user_id: Firebase UID.

    Returns:
        Number of rows deleted.
    """
    conn = _get_conn()
    cursor = conn.execute(
        "DELETE FROM user_swipes WHERE user_id = ?",
        (user_id,),
    )
    conn.commit()
    deleted = cursor.rowcount
    print(f"🧹 [SwipeStore] Cleared {deleted} swipe records for user '{user_id}'")
    return deleted


def get_swipe_history(user_id: str, limit: int = 50) -> List[dict]:
    """
    Returns recent swipe history for a user (for debugging / analytics).

    Args:
        user_id: Firebase UID.
        limit:   Maximum number of records to return.

    Returns:
        List of dicts with keys: user_id, job_id, swipe_action, swiped_at.
    """
    conn = _get_conn()
    rows = conn.execute(
        """
        SELECT user_id, job_id, swipe_action, swiped_at
        FROM user_swipes
        WHERE user_id = ?
        ORDER BY swiped_at DESC
        LIMIT ?
        """,
        (user_id, limit),
    ).fetchall()
    return [dict(row) for row in rows]
