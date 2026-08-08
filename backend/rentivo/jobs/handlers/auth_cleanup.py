from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import Connection, bindparam, text

from rentivo.db import get_engine
from rentivo.jobs.base import JobContext
from rentivo.jobs.payloads import AuthCleanupPayload
from rentivo.jobs.registry import register
from rentivo.settings import settings

AUTH_CLEANUP_BATCH_SIZE = 100
AUTH_CLEANUP_MAX_PURGED_JOBS = 10_000

_EXPIRED_LOGIN_IDS = text(
    "SELECT id FROM api_keys WHERE is_login_token = 1 AND expires_at <= :cutoff ORDER BY id LIMIT :limit"
)
_DELETE_EXPIRED_LOGINS = text(
    "DELETE FROM api_keys WHERE id IN :ids AND is_login_token = 1 AND expires_at <= :cutoff"
).bindparams(bindparam("ids", expanding=True))
_STALE_CHALLENGE_IDS = text(
    "SELECT id FROM auth_challenges WHERE expires_at <= :cutoff OR consumed_at IS NOT NULL ORDER BY id LIMIT :limit"
)
_DELETE_STALE_CHALLENGES = text(
    "DELETE FROM auth_challenges WHERE id IN :ids AND (expires_at <= :cutoff OR consumed_at IS NOT NULL)"
).bindparams(bindparam("ids", expanding=True))
_PURGEABLE_JOB_IDS = text(
    "SELECT id FROM jobs WHERE status IN ('succeeded', 'failed') AND updated_at <= :cutoff ORDER BY id LIMIT :limit"
)
_DELETE_PURGEABLE_JOBS = text(
    "DELETE FROM jobs WHERE id IN :ids AND status IN ('succeeded', 'failed') AND updated_at <= :cutoff"
).bindparams(bindparam("ids", expanding=True))


def _delete_expired_logins(connection: Connection, cutoff: datetime, limit: int) -> int:
    ids = list(
        connection.execute(
            _EXPIRED_LOGIN_IDS,
            {"cutoff": cutoff, "limit": limit},
        ).scalars()
    )
    if not ids:
        return 0
    result = connection.execute(
        _DELETE_EXPIRED_LOGINS,
        {"ids": ids, "cutoff": cutoff},
    )
    return result.rowcount


def _delete_stale_challenges(connection: Connection, cutoff: datetime, limit: int) -> int:
    ids = list(
        connection.execute(
            _STALE_CHALLENGE_IDS,
            {"cutoff": cutoff, "limit": limit},
        ).scalars()
    )
    if not ids:
        return 0
    result = connection.execute(
        _DELETE_STALE_CHALLENGES,
        {"ids": ids, "cutoff": cutoff},
    )
    return result.rowcount


def _delete_old_jobs(connection: Connection, now: datetime, batch_size: int, max_purged: int) -> int:
    """Purge terminal-state job rows past the retention window.

    Payloads are encrypted at rest, but they still carry third-party recipient
    addresses, client IPs, and user agents. Retaining every job ever run grows
    the blast radius of a future key compromise for no operational benefit --
    a finished job's row is only ever read by a human debugging a recent failure.

    Only `succeeded` and `failed` rows are eligible, so a `pending` job waiting
    on a long `run_after` and a `running` job (including this cleanup job's own
    row) are never touched.

    The purge drains in batches of `batch_size` until nothing purgeable is left
    or `max_purged` rows have been removed, so a table that was never purged
    before is worked down over a few runs instead of one batch per run. Deletes
    are keyed by primary key, so the whole drain is cheap to keep in the caller's
    transaction.
    """
    if settings.job_retention_days <= 0:
        return 0
    # `updated_at` on terminal rows is written by the database server clock
    # (SQL NOW()), while this cutoff is a naive UTC timestamp. That only lines up
    # because the production database runs in UTC (stock mariadb:11); a database
    # timezone other than UTC would skew the retention window by that offset.
    cutoff = now - timedelta(days=settings.job_retention_days)
    purged = 0
    while purged < max_purged:
        limit = min(batch_size, max_purged - purged)
        ids = list(connection.execute(_PURGEABLE_JOB_IDS, {"cutoff": cutoff, "limit": limit}).scalars())
        if not ids:
            break
        deleted = connection.execute(_DELETE_PURGEABLE_JOBS, {"ids": ids, "cutoff": cutoff}).rowcount
        purged += deleted
        if deleted < limit:
            # Either the table is drained or a concurrent writer moved rows out
            # of the purgeable set between the select and the delete. Another
            # select would not make progress; the next run picks up the rest.
            break
    return purged


@register("auth.cleanup", model=AuthCleanupPayload)
def handle_auth_cleanup(payload: AuthCleanupPayload, context: JobContext) -> dict[str, int]:
    # Stored timestamps are naive UTC, so the reference instant is normalised to
    # UTC and stripped of its offset before it reaches the comparisons.
    now = (payload.now or datetime.now(UTC)).astimezone(UTC).replace(tzinfo=None)
    with get_engine().begin() as connection:
        # For the auth tables the cutoff is `now` itself: a login token or a
        # challenge is purgeable as soon as it expires.
        login_tokens_deleted = _delete_expired_logins(
            connection,
            now,
            AUTH_CLEANUP_BATCH_SIZE,
        )
        challenges_deleted = _delete_stale_challenges(
            connection,
            now,
            AUTH_CLEANUP_BATCH_SIZE,
        )
        jobs_deleted = _delete_old_jobs(
            connection,
            now,
            AUTH_CLEANUP_BATCH_SIZE,
            AUTH_CLEANUP_MAX_PURGED_JOBS,
        )
    return {
        "login_tokens_deleted": login_tokens_deleted,
        "challenges_deleted": challenges_deleted,
        "jobs_deleted": jobs_deleted,
    }
