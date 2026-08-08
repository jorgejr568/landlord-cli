from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor

import structlog

from rentivo.jobs import handlers  # noqa: F401 — registers handlers
from rentivo.jobs.temporal import activities, workflows
from rentivo.jobs.temporal.client import build_client
from rentivo.jobs.temporal.config import config_from_settings
from rentivo.jobs.temporal.registry import JOB_TYPES

logger = structlog.get_logger(__name__)


def worker_components() -> tuple[list, list]:
    """Return ``(workflows, activities)`` registered on the Temporal worker.

    Both lists are derived from the registration table, plus the one
    job-type-independent finalize activity.

    Pure and dependency-free so it is unit-testable without a Temporal server.
    """
    wfs = list(workflows.workflow_classes())
    acts = [activities.ACTIVITY_BY_JOB_TYPE[job_type] for job_type in JOB_TYPES]
    acts.append(activities.finalize_job_activity)
    return wfs, acts


async def _run_async() -> None:  # pragma: no cover — blocking server loop
    from temporalio.worker import Worker

    cfg = config_from_settings()
    client = await build_client(cfg)
    wfs, acts = worker_components()
    logger.info("temporal_worker_boot", task_queue=cfg.task_queue, namespace=cfg.namespace)
    with ThreadPoolExecutor(max_workers=10) as executor:
        worker = Worker(
            client,
            task_queue=cfg.task_queue,
            workflows=wfs,
            activities=acts,
            activity_executor=executor,
        )
        await worker.run()


def run_temporal_worker() -> None:  # pragma: no cover — process entrypoint
    asyncio.run(_run_async())
