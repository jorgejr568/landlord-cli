import pytest
from temporalio.exceptions import ApplicationError
from temporalio.testing import ActivityEnvironment

from rentivo.jobs import registry
from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.payloads import JobPayload
from rentivo.jobs.temporal import activities
from rentivo.jobs.temporal.registry import JOB_TYPES
from rentivo.models.audit_log import AuditEventType

CONTEXT = JobContext(ulid="01ARZ3NDEKTSV4RRFFQ69G5FAV", attempts=1)


class _BillPayload(JobPayload):
    bill_id: int


def test_run_registered_handler_invokes_handler(clean_registry):
    calls = []
    registry.register("email.send")(lambda p, c: calls.append((p, c)))
    activities.run_registered_handler("email.send", {"to": "x"}, CONTEXT)
    assert calls == [({"to": "x"}, CONTEXT)]


def test_run_registered_handler_missing_handler_is_permanent(clean_registry):
    with pytest.raises(ApplicationError) as exc:
        activities.run_registered_handler("nope", {}, CONTEXT)
    assert exc.value.type == "PermanentJobError"
    assert exc.value.non_retryable is True


def test_run_registered_handler_maps_permanent_job_error(clean_registry):
    def boom(_p, _c):
        raise PermanentJobError("bad input")

    registry.register("email.send")(boom)
    with pytest.raises(ApplicationError) as exc:
        activities.run_registered_handler("email.send", {}, CONTEXT)
    assert exc.value.type == "PermanentJobError"
    assert exc.value.non_retryable is True


def test_run_registered_handler_maps_invalid_payload_to_permanent(clean_registry):
    """The registry decode runs inside the activity, so both drivers agree that
    a payload which cannot match its model is non-retryable."""
    registry.register("email.send", model=_BillPayload)(lambda _p, _c: None)
    with pytest.raises(ApplicationError) as exc:
        activities.run_registered_handler("email.send", {"bill_id": "42"}, CONTEXT)
    assert exc.value.type == "PermanentJobError"
    assert exc.value.non_retryable is True


def test_run_registered_handler_lets_transient_error_propagate(clean_registry):
    def boom(_p, _c):
        raise RuntimeError("network")

    registry.register("email.send")(boom)
    with pytest.raises(RuntimeError, match="network"):
        activities.run_registered_handler("email.send", {}, CONTEXT)


def test_email_send_activity_runs_through_env(clean_registry):
    calls = []
    registry.register("email.send")(lambda p, c: calls.append(p))
    env = ActivityEnvironment()
    env.run(activities.ACTIVITY_BY_JOB_TYPE["email.send"], {"to": "y"})
    assert calls == [{"to": "y"}]


def test_other_activities_run_through_env(clean_registry):
    calls = {}
    payloads = {
        "communication.send": {"a": 1},
        "pdf.render": {"b": 2},
        "recibo.render": {"d": 4},
        "s3.delete": {"c": 3},
        "export.generate": {"e": 5},
        "export.send": {"f": 6},
        "auth.cleanup": {"now": "2026-07-17T12:00:00Z"},
    }
    for job_type in payloads:
        registry.register(job_type)(lambda p, c, _t=job_type: calls.setdefault(_t, p))
    env = ActivityEnvironment()
    for job_type, payload in payloads.items():
        env.run(activities.ACTIVITY_BY_JOB_TYPE[job_type], payload)
    assert calls == payloads


def test_every_registration_table_row_has_an_activity():
    assert set(activities.ACTIVITY_BY_JOB_TYPE) == set(JOB_TYPES)


@pytest.mark.parametrize("job_type", JOB_TYPES)
def test_every_activity_forwards_the_workflow_job_identity(clean_registry, monkeypatch, job_type):
    """Job identity is unconditional: every activity reports the ULID carried by
    the ``job-<ulid>`` workflow id, not just the render ones."""
    received = []
    registry.register(job_type)(lambda payload, context: received.append((payload, context)))
    monkeypatch.setattr(
        activities.activity,
        "info",
        lambda: type("Info", (), {"workflow_id": "job-01ARZ3NDEKTSV4RRFFQ69G5FAV", "attempt": 3})(),
    )
    original_payload = {"bill_id": 42}

    activities.ACTIVITY_BY_JOB_TYPE[job_type](original_payload)

    assert received == [({"bill_id": 42}, JobContext(ulid="01ARZ3NDEKTSV4RRFFQ69G5FAV", attempts=3))]
    assert original_payload == {"bill_id": 42}


def test_job_context_is_empty_outside_a_job_workflow(monkeypatch):
    """Only ``TemporalJobBackend`` mints ``job-<ulid>`` ids; anything else has no
    durable job identity to report."""
    monkeypatch.setattr(
        activities.activity,
        "info",
        lambda: type("Info", (), {"workflow_id": "some-other-workflow", "attempt": 1})(),
    )
    assert activities.job_context() == JobContext(ulid="", attempts=1)


def test_open_audit_returns_audit_and_close(monkeypatch):
    from sqlalchemy import create_engine, text
    from sqlalchemy.pool import StaticPool

    import rentivo.db as db_mod
    from rentivo.services.audit_service import AuditService
    from tests.conftest import SCHEMA_DDL

    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    with eng.connect() as c:
        for stmt in SCHEMA_DDL.strip().split(";"):
            if stmt.strip():
                c.execute(text(stmt))
        c.commit()

    monkeypatch.setattr(db_mod, "get_engine", lambda: eng)

    audit, close = activities._open_audit()
    assert isinstance(audit, AuditService)
    # A real safe_log against the schema-backed connection must not raise.
    audit.safe_log(
        event_type="job.succeeded",
        source="worker",
        actor_id=None,
        actor_username="",
        entity_type="job",
        entity_uuid="01OPEN",
        previous_state=None,
        new_state={"ok": True},
    )
    close()
    eng.dispose()


def test_finalize_job_activity_runs_through_env(monkeypatch):
    logged = []
    monkeypatch.setattr(activities, "_open_audit", lambda: (_FakeAudit(logged), _noop_close))
    env = ActivityEnvironment()
    env.run(
        activities.finalize_job_activity,
        {"kind": "succeeded", "job_type": "email.send", "ulid": "01N", "attempts": 1},
    )
    assert logged[0]["event_type"] == AuditEventType.JOB_SUCCEEDED


def test_finalize_job_succeeded_writes_audit(monkeypatch):
    logged = []
    monkeypatch.setattr(activities, "_open_audit", lambda: (_FakeAudit(logged), _noop_close))
    activities.finalize_job(
        {"kind": "succeeded", "job_type": "email.send", "ulid": "01J", "attempts": 1, "payload": {}}
    )
    assert logged[0]["event_type"] == AuditEventType.JOB_SUCCEEDED
    assert logged[0]["new_state"] == {"job_type": "email.send", "ulid": "01J", "attempts": 1}


def test_finalize_job_failed_runs_fail_hook(clean_registry, monkeypatch):
    logged = []
    monkeypatch.setattr(activities, "_open_audit", lambda: (_FakeAudit(logged), _noop_close))
    hook_calls = []
    registry.register_on_fail("pdf.render")(lambda p: hook_calls.append(p))

    activities.finalize_job(
        {
            "kind": "failed",
            "job_type": "pdf.render",
            "ulid": "01K",
            "attempts": 5,
            "error": "boom",
            "payload": {"bill_id": 3},
        }
    )
    assert logged[0]["event_type"] == AuditEventType.JOB_FAILED
    assert logged[0]["new_state"]["error"] == "boom"
    assert hook_calls == [{"bill_id": 3}]


def test_finalize_job_failed_swallows_fail_hook_error(clean_registry, monkeypatch):
    monkeypatch.setattr(activities, "_open_audit", lambda: (_FakeAudit([]), _noop_close))

    def bad_hook(_p):
        raise RuntimeError("hook blew up")

    registry.register_on_fail("pdf.render")(bad_hook)
    # Must not raise.
    activities.finalize_job(
        {"kind": "failed", "job_type": "pdf.render", "ulid": "01K", "attempts": 5, "error": "x", "payload": {}}
    )


def test_finalize_job_retry_includes_next_run_after(monkeypatch):
    logged = []
    monkeypatch.setattr(activities, "_open_audit", lambda: (_FakeAudit(logged), _noop_close))
    activities.finalize_job(
        {
            "kind": "retry",
            "job_type": "email.send",
            "ulid": "01M",
            "attempts": 2,
            "error": "transient",
            "next_run_after": "2026-01-01T00:05:00+00:00",
            "payload": {},
        }
    )
    assert logged[0]["event_type"] == AuditEventType.JOB_RETRY_SCHEDULED
    assert logged[0]["new_state"]["next_run_after"] == "2026-01-01T00:05:00+00:00"


def _noop_close():
    pass


class _FakeAudit:
    def __init__(self, sink):
        self.sink = sink

    def safe_log(self, **kwargs):
        self.sink.append(kwargs)
        return None
