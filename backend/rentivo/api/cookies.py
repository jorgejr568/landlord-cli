"""Authentication cookie helpers shared by the auth route modules.

Every ``Set-Cookie`` header the API emits for authentication state is written
here so the ``__Host-`` names and the secure/httponly/samesite/path attributes
stay defined in exactly one place.
"""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import Response

from rentivo.api.authentication import ACCESS_COOKIE_NAME
from rentivo.api.csrf import CSRF_COOKIE_NAME
from rentivo.settings import settings


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def set_access_cookie(response: Response, credential: str) -> None:
    response.set_cookie(
        settings.access_cookie_name,
        credential,
        max_age=settings.api_key_login_ttl_seconds,
        secure=settings.cookie_secure,
        httponly=True,
        samesite="lax",
        path="/",
    )


def set_challenge_cookie(response: Response, nonce: str) -> None:
    response.set_cookie(
        settings.challenge_cookie_name,
        nonce,
        max_age=settings.auth_challenge_ttl_seconds,
        secure=settings.cookie_secure,
        httponly=True,
        samesite="lax",
        path="/",
    )


def delete_cookie(response: Response, name: str, *, httponly: bool) -> None:
    response.delete_cookie(
        name,
        path="/",
        secure=settings.cookie_secure,
        httponly=httponly,
        samesite="lax",
    )


def delete_challenge_cookie(response: Response) -> None:
    delete_cookie(response, settings.challenge_cookie_name, httponly=True)


def clear_auth_cookies(response: Response, *, include_challenge: bool) -> None:
    # Fall back to the module constants captured at import: an environment that
    # blanks a cookie name must still clear the cookie that was actually set,
    # never emit a nameless ``Set-Cookie`` that leaves the session live.
    delete_cookie(response, settings.access_cookie_name or ACCESS_COOKIE_NAME, httponly=True)
    delete_cookie(response, settings.csrf_cookie_name or CSRF_COOKIE_NAME, httponly=False)
    if include_challenge:
        delete_challenge_cookie(response)


def copy_set_cookies(source: Response, target: Response) -> None:
    for value in source.headers.getlist("set-cookie"):
        target.headers.append("set-cookie", value)
