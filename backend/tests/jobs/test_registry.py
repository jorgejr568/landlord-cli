import pytest

from rentivo.jobs import registry
from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.payloads import JobPayload

CONTEXT = JobContext(ulid="01ARZ3NDEKTSV4RRFFQ69G5FAV", attempts=1)


class _BillPayload(JobPayload):
    bill_id: int


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
