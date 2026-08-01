from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import Connection, bindparam, text

from rentivo.db import get_engine
from rentivo.jobs.base import JobContext
from rentivo.jobs.payloads import AuthCleanupPayload
from rentivo.jobs.registry import register
from rentivo.settings import settings

AUTH_CLEANUP_BATCH_SIZE = 100

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


def _delete_old_jobs(connection: Connection, now: datetime, limit: int) -> int:
    """Purge terminal-state job rows past the retention window.

    Payloads are encrypted at rest, but they still carry third-party recipient
    addresses, client IPs, and user agents. Retaining every job ever run grows
    the blast radius of a future key compromise for no operational benefit --
    a finished job's row is only ever read by a human debugging a recent failure.

    Only `succeeded` and `failed` rows are eligible, so a `pending` job waiting
    on a long `run_after` and a `running` job (including this cleanup job's own
    row) are never touched.
    """
    if settings.job_retention_days <= 0:
        return 0
    cutoff = now - timedelta(days=settings.job_retention_days)
    ids = list(connection.execute(_PURGEABLE_JOB_IDS, {"cutoff": cutoff, "limit": limit}).scalars())
    if not ids:
        return 0
    result = connection.execute(_DELETE_PURGEABLE_JOBS, {"ids": ids, "cutoff": cutoff})
    return result.rowcount


@register("auth.cleanup", model=AuthCleanupPayload)
def handle_auth_cleanup(payload: AuthCleanupPayload, context: JobContext) -> dict[str, int]:
    # Stored timestamps are naive UTC, so the cutoff is normalised to UTC and
    # stripped of its offset before it reaches the comparisons.
    cutoff = (payload.now or datetime.now(UTC)).astimezone(UTC).replace(tzinfo=None)
    with get_engine().begin() as connection:
        login_tokens_deleted = _delete_expired_logins(
            connection,
            cutoff,
            AUTH_CLEANUP_BATCH_SIZE,
        )
        challenges_deleted = _delete_stale_challenges(
            connection,
            cutoff,
            AUTH_CLEANUP_BATCH_SIZE,
        )
        jobs_deleted = _delete_old_jobs(
            connection,
            cutoff,
            AUTH_CLEANUP_BATCH_SIZE,
        )
    return {
        "login_tokens_deleted": login_tokens_deleted,
        "challenges_deleted": challenges_deleted,
        "jobs_deleted": jobs_deleted,
    }
