from __future__ import annotations

from importlib import import_module
from typing import Callable

from pydantic import BaseModel, ValidationError

from rentivo.jobs.base import JobContext, PermanentJobError

HandlerFn = Callable[..., object]
HandlerOnFailFn = Callable[[dict], None]

# The payload model is stamped on the handler function rather than kept in a
# side table, so it travels with the handler: a registry that is cleared and
# repopulated (tests) or rebuilt through the lazy builtin import below can never
# pair a handler with the wrong model.
_MODEL_ATTR = "__job_payload_model__"

_BUILTIN_HANDLERS = {
    "auth.cleanup": ("rentivo.jobs.handlers.auth_cleanup", "handle_auth_cleanup"),
}

_REGISTRY: dict[str, HandlerFn] = {}
_FAIL_HOOKS: dict[str, HandlerOnFailFn] = {}


def register(job_type: str, *, model: type[BaseModel] | None = None) -> Callable[[HandlerFn], HandlerFn]:
    """Register the handler for ``job_type``.

    ``model`` is the payload model this job type decodes to; ``dispatch`` hands
    the handler an instance of it. Registering without one hands the handler the
    raw payload dict.
    """

    def deco(fn: HandlerFn) -> HandlerFn:
        if job_type in _REGISTRY:
            raise ValueError(f"Handler already registered for job_type {job_type!r}")
        if model is not None:
            setattr(fn, _MODEL_ATTR, model)
        _REGISTRY[job_type] = fn
        return fn

    return deco


def get(job_type: str) -> HandlerFn | None:
    handler = _REGISTRY.get(job_type)
    if handler is None and job_type in _BUILTIN_HANDLERS:
        module_name, handler_name = _BUILTIN_HANDLERS[job_type]
        handler = getattr(import_module(module_name), handler_name)
        _REGISTRY[job_type] = handler
    return handler


def payload_model(handler: HandlerFn) -> type[BaseModel] | None:
    """The payload model ``handler`` was registered with, if any."""
    return getattr(handler, _MODEL_ATTR, None)


def _decode_failure_message(job_type: str, exc: ValidationError) -> str:
    """Describe a decode failure without echoing any of the payload.

    ``str(ValidationError)`` embeds the offending input — and for a missing
    field that input is the *whole* payload dict, recipient addresses and
    reset-link tails included. This message is stored verbatim on the job row,
    copied into the ``JOB_FAILED`` audit entry and logged, none of which any
    redactor can reach into, so only the field location and the machine error
    type ever leave here.
    """
    details = ", ".join(
        f"{'.'.join(str(part) for part in error['loc']) or '<payload>'}: {error['type']}"
        for error in exc.errors(include_url=False, include_input=False)
    )
    return f"invalid {job_type} payload: {details}"


def dispatch(job_type: str, handler: HandlerFn, payload: dict, context: JobContext) -> object:
    """Decode ``payload`` into the handler's payload model and invoke it.

    The single place a stored payload is validated, so every driver — the
    database worker and the Temporal activity alike — inherits the same decode
    and the same verdict: a payload that does not match its model cannot start
    matching on a retry, so it fails permanently.
    """
    model = payload_model(handler)
    if model is None:
        return handler(payload, context)
    try:
        decoded = model.model_validate(payload)
    except ValidationError as exc:
        raise PermanentJobError(_decode_failure_message(job_type, exc)) from exc
    return handler(decoded, context)


def register_on_fail(job_type: str) -> Callable[[HandlerOnFailFn], HandlerOnFailFn]:
    def deco(fn: HandlerOnFailFn) -> HandlerOnFailFn:
        if job_type in _FAIL_HOOKS:
            raise ValueError(f"Fail hook already registered for job_type {job_type!r}")
        _FAIL_HOOKS[job_type] = fn
        return fn

    return deco


def get_fail_hook(job_type: str) -> HandlerOnFailFn | None:
    return _FAIL_HOOKS.get(job_type)
