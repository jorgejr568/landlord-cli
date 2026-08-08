"""Unit coverage for the shared authentication cookie helpers."""

from __future__ import annotations

from starlette.responses import Response

from rentivo.api.authentication import ACCESS_COOKIE_NAME
from rentivo.api.cookies import clear_auth_cookies
from rentivo.api.csrf import CSRF_COOKIE_NAME
from rentivo.settings import settings


def _cleared_names(response: Response) -> list[str]:
    return [value.split("=", 1)[0] for value in response.headers.getlist("set-cookie")]


def test_clear_auth_cookies_uses_the_configured_names():
    response = Response()

    clear_auth_cookies(response, include_challenge=True)

    assert _cleared_names(response) == [
        settings.access_cookie_name,
        settings.csrf_cookie_name,
        settings.challenge_cookie_name,
    ]


def test_clear_auth_cookies_skips_the_challenge_cookie_when_not_asked():
    response = Response()

    clear_auth_cookies(response, include_challenge=False)

    assert settings.challenge_cookie_name not in _cleared_names(response)


def test_clear_auth_cookies_falls_back_when_a_cookie_name_is_blank(monkeypatch):
    """A blanked-out cookie name must not turn logout into a nameless
    ``Set-Cookie`` that leaves the session cookie live in the browser; the
    helper falls back to the names captured at import."""
    monkeypatch.setattr(settings, "access_cookie_name", "")
    monkeypatch.setattr(settings, "csrf_cookie_name", "")
    response = Response()

    clear_auth_cookies(response, include_challenge=False)

    assert _cleared_names(response) == [ACCESS_COOKIE_NAME, CSRF_COOKIE_NAME]
