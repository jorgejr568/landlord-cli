import pytest
from pydantic import model_validator

from rentivo.jobs import registry
from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.payloads import JobPayload

CONTEXT = JobContext(ulid="01ARZ3NDEKTSV4RRFFQ69G5FAV", attempts=1)


class _BillPayload(JobPayload):
    bill_id: int


class _ContactPayload(JobPayload):
    event: str
    to_email: str


class _PairPayload(JobPayload):
    left: int
    right: int | None = None

    @model_validator(mode="after")
    def _needs_both(self) -> "_PairPayload":
        if self.right is None:
            raise ValueError("left requires right")
        return self


@pytest.fixture(autouse=True)
def _clear_registry():
    """Each test starts from an empty registry."""
    registry._REGISTRY.clear()
    yield
    registry._REGISTRY.clear()


def test_register_adds_handler():
    @registry.register("foo.bar")
    def handler(payload: dict, context: JobContext) -> None:
        return None

    assert registry.get("foo.bar") is handler


def test_register_returns_the_function_unchanged():
    def handler(payload: dict, context: JobContext) -> None:
        return None

    decorated = registry.register("foo.bar")(handler)
    assert decorated is handler


def test_duplicate_register_raises():
    @registry.register("foo.bar")
    def first(payload: dict, context: JobContext) -> None:
        return None

    with pytest.raises(ValueError, match="foo.bar"):

        @registry.register("foo.bar")
        def second(payload: dict, context: JobContext) -> None:
            return None


def test_get_returns_none_for_unknown_type():
    assert registry.get("nope.never") is None


def test_dispatch_decodes_the_payload_into_the_registered_model():
    seen = []
    handler = registry.register("foo.bar", model=_BillPayload)(lambda payload, context: seen.append((payload, context)))

    result = registry.dispatch("foo.bar", handler, {"bill_id": 42, "_otel": {}}, CONTEXT)

    assert result is None
    assert seen == [(_BillPayload(bill_id=42), CONTEXT)]


def test_dispatch_returns_the_handler_result():
    handler = registry.register("foo.bar", model=_BillPayload)(lambda payload, context: payload.bill_id)

    assert registry.dispatch("foo.bar", handler, {"bill_id": 7}, CONTEXT) == 7


def test_dispatch_without_a_model_passes_the_raw_payload():
    seen = []
    handler = registry.register("foo.bar")(lambda payload, context: seen.append(payload))

    registry.dispatch("foo.bar", handler, {"anything": True}, CONTEXT)

    assert seen == [{"anything": True}]


def test_dispatch_turns_a_validation_error_into_a_permanent_failure():
    handler = registry.register("foo.bar", model=_BillPayload)(lambda payload, context: None)

    with pytest.raises(PermanentJobError, match="invalid foo.bar payload"):
        registry.dispatch("foo.bar", handler, {"bill_id": "42"}, CONTEXT)


def test_decode_failure_names_the_field_and_the_error_type():
    handler = registry.register("foo.bar", model=_BillPayload)(lambda payload, context: None)

    with pytest.raises(PermanentJobError) as exc:
        registry.dispatch("foo.bar", handler, {"bill_id": "42"}, CONTEXT)

    assert str(exc.value) == "invalid foo.bar payload: bill_id: int_type"


def test_decode_failure_reports_every_bad_field():
    handler = registry.register("foo.baz", model=_ContactPayload)(lambda payload, context: None)

    with pytest.raises(PermanentJobError) as exc:
        registry.dispatch("foo.baz", handler, {}, CONTEXT)

    assert str(exc.value) == "invalid foo.baz payload: event: missing, to_email: missing"


def test_decode_failure_never_echoes_the_payload():
    """The message is stored on the job row, the JOB_FAILED audit entry and the
    logs, none of which any redactor can reach into — so nothing from the
    payload may appear in it. Pydantic's own ``str(ValidationError)`` embeds the
    input, and for a missing field that input is the entire payload dict."""
    handler = registry.register("foo.baz", model=_ContactPayload)(lambda payload, context: None)
    sentinel = "SECRET-TOKEN@example.com"

    with pytest.raises(PermanentJobError) as exc:
        registry.dispatch("foo.baz", handler, {"to_email": sentinel}, CONTEXT)

    assert sentinel not in str(exc.value)
    assert str(exc.value) == "invalid foo.baz payload: event: missing"


def test_decode_failure_labels_a_whole_payload_error():
    """A model-level validator reports an empty location; it still needs a name."""
    handler = registry.register("foo.qux", model=_PairPayload)(lambda payload, context: None)

    with pytest.raises(PermanentJobError) as exc:
        registry.dispatch("foo.qux", handler, {"left": 1}, CONTEXT)

    assert str(exc.value) == "invalid foo.qux payload: <payload>: value_error"


@pytest.fixture(autouse=True)
def _clear_fail_hooks():
    """Each test starts from an empty fail-hook registry."""
    registry._FAIL_HOOKS.clear()
    yield
    registry._FAIL_HOOKS.clear()


def test_register_on_fail_adds_hook():
    @registry.register_on_fail("foo.bar")
    def hook(payload: dict) -> None:
        return None

    assert registry.get_fail_hook("foo.bar") is hook


def test_register_on_fail_returns_function_unchanged():
    def hook(payload: dict) -> None:
        return None

    decorated = registry.register_on_fail("foo.bar")(hook)
    assert decorated is hook


def test_duplicate_register_on_fail_raises():
    @registry.register_on_fail("foo.bar")
    def first(payload: dict) -> None:
        return None

    with pytest.raises(ValueError, match="foo.bar"):

        @registry.register_on_fail("foo.bar")
        def second(payload: dict) -> None:
            return None


def test_get_fail_hook_returns_none_for_unknown_type():
    assert registry.get_fail_hook("nope.never") is None
