"""Builders for the JSON responses that carry an authenticated session.

Three flows end here: password/Google/mobile login, MFA verification, and the
``GET /auth/session`` refresh. They all need a freshly issued CSRF token inside
the bootstrap payload, and the login flows additionally deliver the access
credential either as a ``__Host-`` cookie or in the response body.
"""

from __future__ import annotations

from typing import Any

from fastapi.responses import JSONResponse, Response

from rentivo.api.cookies import copy_set_cookies, set_access_cookie, set_challenge_cookie
from rentivo.api.csrf import issue_csrf_token
from rentivo.api.principal import Principal
from rentivo.api.schemas.auth import (
    AnalyticsEvent,
    AuthenticatedResponse,
    BootstrapAnalytics,
    BootstrapResponse,
    CredentialTransport,
    MFARequiredResponse,
    SessionResponse,
)
from rentivo.services.login_service import LoginResult
from rentivo.settings import settings


def _bootstrap(
    principal: Principal,
    bootstrap: dict[str, Any],
    *,
    analytics_event: dict[str, Any] | None,
) -> tuple[BootstrapResponse, Response]:
    """Render the bootstrap payload and the CSRF cookie that belongs with it."""
    csrf_cookie = Response()
    csrf_token = issue_csrf_token(csrf_cookie, principal)
    payload = BootstrapResponse.model_validate({**bootstrap, "csrf_token": csrf_token})
    if analytics_event is not None:
        payload = payload.model_copy(
            update={
                "analytics": BootstrapAnalytics(
                    gtm_container_id=payload.analytics.gtm_container_id,
                    events=(*payload.analytics.events, AnalyticsEvent.model_validate(analytics_event)),
                )
            }
        )
    return payload, csrf_cookie


def _no_store(response: JSONResponse) -> JSONResponse:
    response.headers["Cache-Control"] = "no-store"
    return response


def login_response(
    result: LoginResult,
    *,
    credential_transport: CredentialTransport = "cookie",
) -> JSONResponse:
    """Response for a completed login, carrying the newly issued credential."""
    principal = Principal(
        user=result.user,
        api_key=result.api_key,
        source="web" if credential_transport == "cookie" else "mobile",
    )
    bootstrap, csrf_cookie = _bootstrap(principal, result.bootstrap, analytics_event=result.analytics_event)
    payload = AuthenticatedResponse.model_validate(
        {
            "credential_transport": credential_transport,
            "bootstrap": bootstrap,
            **(
                {
                    "access_token": result.access_credential,
                    "token_type": "Bearer",
                    "expires_in": settings.api_key_login_ttl_seconds,
                }
                if credential_transport == "body"
                else {}
            ),
        }
    )
    response = JSONResponse(payload.model_dump(mode="json"))
    if credential_transport == "cookie":
        copy_set_cookies(csrf_cookie, response)
        set_access_cookie(response, result.access_credential)
    return _no_store(response)


def session_response(principal: Principal, bootstrap: dict[str, Any]) -> JSONResponse:
    """Response for a session refresh: bootstrap only, no credential re-issued."""
    bootstrap_payload, csrf_cookie = _bootstrap(principal, bootstrap, analytics_event=None)
    payload = SessionResponse(bootstrap=bootstrap_payload)
    response = JSONResponse(payload.model_dump(mode="json"))
    if principal.source != "mobile":
        copy_set_cookies(csrf_cookie, response)
    return _no_store(response)


def mfa_response(
    result: LoginResult,
    *,
    credential_transport: CredentialTransport = "cookie",
) -> JSONResponse:
    """202 response telling the client which second factors are accepted."""
    payload = MFARequiredResponse.model_validate(
        {
            "credential_transport": credential_transport,
            "challenge_id": result.challenge_id,
            "methods": result.methods,
            **({"challenge_token": result.challenge_nonce} if credential_transport == "body" else {}),
        }
    )
    response = JSONResponse(payload.model_dump(mode="json"), status_code=202)
    if credential_transport == "cookie":
        set_challenge_cookie(response, result.challenge_nonce)
    return _no_store(response)
