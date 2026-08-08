from __future__ import annotations

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError, ApplicationError

with workflow.unsafe.imports_passed_through():
    from rentivo.jobs.backoff import backoff_seconds
    from rentivo.jobs.temporal.config import config_from_settings
    from rentivo.jobs.temporal.registry import JOB_WORKFLOWS
    from rentivo.jobs.temporal.retry import is_permanent, should_give_up

_FINALIZE = "rentivo.finalize_job"


def _error_text(err: BaseException) -> str:
    cause = getattr(err, "cause", None) or err
    msg = getattr(cause, "message", None) or str(cause)
    return msg[:4096]


def _error_type(err: BaseException) -> str | None:
    cause = getattr(err, "cause", None)
    return getattr(cause, "type", None) if isinstance(cause, ApplicationError) else None


async def _run_job(job_type: str, payload: dict, ulid: str, max_attempts: int) -> None:
    """Shared orchestration mirroring the database worker's retry/backoff/
    dead-letter semantics. Each per-job-type workflow delegates here.

    ``job_type`` doubles as the activity name (they're registered 1:1)."""
    cfg = config_from_settings()
    attempt = 0
    while True:
        attempt += 1
        try:
            await workflow.execute_activity(
                job_type,
                payload,
                start_to_close_timeout=timedelta(seconds=cfg.activity_timeout_seconds),
                # The workflow owns retries/backoff; the activity runs once per loop.
                retry_policy=RetryPolicy(maximum_attempts=1),
            )
        except ActivityError as err:
            permanent = is_permanent(_error_type(err))
            error_text = _error_text(err)
            if should_give_up(attempt, max_attempts, permanent):
                await _finalize(
                    {
                        "kind": "failed",
                        "job_type": job_type,
                        "ulid": ulid,
                        "attempts": attempt,
                        "error": error_text,
                        "payload": payload,
                    }
                )
                raise
            wait = backoff_seconds(attempt)
            await _finalize(
                {
                    "kind": "retry",
                    "job_type": job_type,
                    "ulid": ulid,
                    "attempts": attempt,
                    "error": error_text,
                    "next_run_after": _now_plus_iso(wait),
                    "payload": payload,
                }
            )
            await workflow.sleep(timedelta(seconds=wait))
            continue
        else:
            await _finalize({"kind": "succeeded", "job_type": job_type, "ulid": ulid, "attempts": attempt})
            return


def _now_plus_iso(seconds: int) -> str:
    return (workflow.now() + timedelta(seconds=seconds)).isoformat()


async def _finalize(event: dict) -> None:
    await workflow.execute_activity(
        _FINALIZE,
        event,
        start_to_close_timeout=timedelta(seconds=60),
        retry_policy=RetryPolicy(maximum_attempts=3),
    )


def _build_workflow(job_type: str, workflow_name: str) -> type:
    """Build the workflow class for one row of the registration table.

    Every per-job-type workflow is the same five lines with a different job
    type, so the class is generated instead of transcribed. ``workflow_name``
    is passed through to ``@workflow.defn`` verbatim: it is the name recorded
    in Temporal history and must not change.
    """

    async def run(self, payload: dict, ulid: str, max_attempts: int) -> None:
        await _run_job(job_type, payload, ulid, max_attempts)

    # Temporal requires the run method to be a non-local, module-level method of
    # the workflow class: it resolves both by qualified name when rehydrating a
    # workflow inside the sandbox. ``_install_workflows`` makes that true, so
    # the closure advertises the qualified name it is about to be installed as.
    run.__qualname__ = f"{workflow_name}.run"
    cls = type(workflow_name, (), {"__module__": __name__, "__qualname__": workflow_name, "run": workflow.run(run)})
    return workflow.defn(name=workflow_name)(cls)


def _install_workflows() -> None:
    """Publish one module-level workflow class per registration-table row.

    Temporal's workflow sandbox re-imports this module and resolves each class
    by module + qualified name, so the generated classes must be reachable as
    module attributes under exactly the names they were built with.
    """
    for job_type, workflow_name in JOB_WORKFLOWS:
        globals()[workflow_name] = _build_workflow(job_type, workflow_name)


_install_workflows()


def workflow_classes() -> tuple[type, ...]:
    """The generated workflow classes, in registration-table order."""
    return tuple(globals()[workflow_name] for _, workflow_name in JOB_WORKFLOWS)


def workflow_by_type() -> dict[str, type]:
    """Map each job type to the workflow class that runs it."""
    return {job_type: globals()[workflow_name] for job_type, workflow_name in JOB_WORKFLOWS}
