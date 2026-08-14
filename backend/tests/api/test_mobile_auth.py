"""Contract for the Turnstile-free native auth endpoints and the AASA manifest.

`/auth/mobile/login` and `/auth/mobile/signup` are the only credential
endpoints a native client can reach without a browser, so they replace the
Turnstile widget with two rate-limit budgets and a fixed delay in front of
every failure. These tests pin all three: the delay fires (with the real
4-second argument) on failures and never on success, both budgets are charged
independently, and no response ever carries a cookie.
"""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

import rentivo.api.routes.auth as auth_routes
from rentivo.api.app import create_app
from rentivo.api.authentication import ACCESS_COOKIE_NAME
from rentivo.api.csrf import CSRF_COOKIE_NAME
from rentivo.api.errors import ProblemException
from rentivo.models.audit_log import AuditEventType
from rentivo.settings import settings
from tests.api.routes.test_auth import (
    ACCESS_SECRET,
    BOOTSTRAP,
    CHALLENGE_ID,
    CHALLENGE_NONCE,
    MFA_RESULT,
    USER,
    AuthHarness,
    build_auth_harness,
)

LOGIN_PATH = "/api/v1/auth/mobile/login"
SIGNUP_PATH = "/api/v1/auth/mobile/signup"
AASA_PATH = "/.well-known/apple-app-site-association"

LOGIN_PAYLOAD = {"email": USER.email, "password": "correct"}
SIGNUP_PAYLOAD = {"email": USER.email, "password": "correct horse battery staple"}


@pytest.fixture()
def auth_harness(monkeypatch: pytest.MonkeyPatch) -> AuthHarness:
    return build_auth_harness(monkeypatch)


@pytest.fixture(autouse=True)
def tarpit_calls(monkeypatch: pytest.MonkeyPatch) -> list[float]:
    """Record every tarpit delay and collapse it, so the suite stays fast.

    The route still awaits the real `asyncio.sleep`; only the duration is
    dropped, which keeps the assertion about *what* was requested honest.
    """
    real_sleep = asyncio.sleep
    calls: list[float] = []

    async def instant_sleep(delay: float, *args: object, **kwargs: object) -> object:
        calls.append(delay)
        return await real_sleep(0, *args, **kwargs)

    monkeypatch.setattr(auth_routes.asyncio, "sleep", instant_sleep)
    return calls


def _assert_cookie_free(response: object) -> None:
    assert response.headers.get_list("set-cookie") == []
    assert ACCESS_COOKIE_NAME not in response.cookies
    assert CSRF_COOKIE_NAME not in response.cookies
    assert settings.challenge_cookie_name not in response.cookies


def _client_from(harness: AuthHarness, ip: str) -> TestClient:
    return TestClient(harness.app, client=(ip, 50000))


def _rate_identities(harness: AuthHarness, action: str) -> list[str]:
    return [identity for logged_action, identity in harness.rate_limit.calls if logged_action == action]


def test_mobile_login_returns_a_cookie_free_bearer_session_without_delay(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "authenticated"
    assert payload["credential_transport"] == "body"
    assert payload["access_token"] == ACCESS_SECRET
    assert payload["token_type"] == "Bearer"
    assert payload["expires_in"] == settings.api_key_login_ttl_seconds
    assert payload["bootstrap"]["user"] == BOOTSTRAP["user"]
    assert response.headers["cache-control"] == "no-store"
    _assert_cookie_free(response)
    assert tarpit_calls == []
    assert auth_harness.login.login_calls[0][1]["source"] == "mobile"


def test_mobile_login_never_asks_turnstile_to_verify_anything(
    auth_harness: AuthHarness,
) -> None:
    auth_harness.turnstile.allowed = False

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 200


def test_mobile_login_rejects_a_turnstile_token_it_would_never_check(
    auth_harness: AuthHarness,
) -> None:
    response = auth_harness.client.post(
        LOGIN_PATH,
        json={**LOGIN_PAYLOAD, "turnstile_token": "ignored"},
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert auth_harness.login.login_calls == []


def test_mobile_login_rejects_a_credential_transport_it_does_not_negotiate(
    auth_harness: AuthHarness,
) -> None:
    response = auth_harness.client.post(
        LOGIN_PATH,
        json={**LOGIN_PAYLOAD, "credential_transport": "cookie"},
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert auth_harness.login.login_calls == []


def test_mobile_login_requiring_mfa_returns_202_with_the_challenge_token_in_the_body(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = MFA_RESULT

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 202
    assert response.json() == {
        "status": "mfa_required",
        "challenge_id": CHALLENGE_ID,
        "challenge_token": CHALLENGE_NONCE,
        "credential_transport": "body",
        "methods": ["totp", "recovery", "passkey"],
    }
    assert response.headers["cache-control"] == "no-store"
    _assert_cookie_free(response)
    assert tarpit_calls == []


def test_mobile_login_clears_only_the_email_budget_on_success(
    auth_harness: AuthHarness,
) -> None:
    assert auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD).status_code == 200

    assert ("mobile_auth_email", USER.email) not in auth_harness.rate_limit.attempts
    assert auth_harness.rate_limit.attempts[("mobile_auth_ip", "testclient")] == 1


def test_rejected_mobile_credentials_are_tarpitted_audited_and_indistinguishable(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.reject_login = True

    unknown = auth_harness.client.post(LOGIN_PATH, json={"email": "nobody@example.com", "password": "x"})
    wrong = auth_harness.client.post(LOGIN_PATH, json={"email": USER.email, "password": "wrong"})

    assert [unknown.status_code, wrong.status_code] == [401, 401]
    assert unknown.json()["code"] == "invalid_credentials"
    assert unknown.json()["detail"] == wrong.json()["detail"] == "E-mail ou senha inválidos."
    assert "nobody@example.com" not in unknown.text
    assert unknown.headers["X-Rentivo-Analytics-Reason"] == "bad_credentials"
    assert tarpit_calls == [4.0, 4.0]
    actors = [args[0] for args, _kwargs in auth_harness.audit.calls]
    assert [args[1] for args, _kwargs in auth_harness.audit.calls] == [AuditEventType.USER_LOGIN_FAILED] * 2
    assert [actor.source for actor in actors] == ["mobile", "mobile"]
    _assert_cookie_free(unknown)


def test_mobile_login_tarpits_a_none_result_the_same_as_a_raised_rejection(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"
    assert tarpit_calls == [4.0]
    assert len(auth_harness.audit.calls) == 1


def test_mobile_login_passes_through_problems_that_are_not_bad_credentials(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    def refuse(*_args: object, **_kwargs: object) -> None:
        raise ProblemException.forbidden("account_disabled", "Conta indisponível.")

    auth_harness.login.login = refuse

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 403
    assert response.json()["code"] == "account_disabled"
    assert tarpit_calls == []
    assert auth_harness.audit.calls == []


def test_a_fifth_mobile_login_from_one_ip_is_rate_limited_across_distinct_emails(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None
    attempts = [
        auth_harness.client.post(LOGIN_PATH, json={"email": f"user{index}@example.com", "password": "wrong"})
        for index in range(4)
    ]

    limited = auth_harness.client.post(LOGIN_PATH, json={"email": "user4@example.com", "password": "wrong"})

    assert [response.status_code for response in attempts] == [401] * 4
    assert limited.status_code == 429
    assert limited.json()["code"] == "login_rate_limited"
    assert limited.headers["X-Rentivo-Analytics-Reason"] == "rate_limited"
    assert tarpit_calls == [4.0] * 5
    assert _rate_identities(auth_harness, "mobile_auth_ip") == ["testclient"] * 5
    assert len(set(_rate_identities(auth_harness, "mobile_auth_email"))) == 5
    _assert_cookie_free(limited)


def test_a_fifth_mobile_login_for_one_email_is_rate_limited_across_distinct_ips(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None
    payload = {"email": " PERSON@example.com ", "password": "wrong"}
    attempts = [_client_from(auth_harness, f"203.0.113.{index}").post(LOGIN_PATH, json=payload) for index in range(4)]

    limited = _client_from(auth_harness, "203.0.113.4").post(LOGIN_PATH, json=payload)

    assert [response.status_code for response in attempts] == [401] * 4
    assert limited.status_code == 429
    assert limited.json()["code"] == "login_rate_limited"
    assert tarpit_calls == [4.0] * 5
    assert _rate_identities(auth_harness, "mobile_auth_email") == [USER.email] * 5
    assert _rate_identities(auth_harness, "mobile_auth_ip") == [f"203.0.113.{index}" for index in range(5)]
    assert auth_harness.login.login_calls[0][1]["client_ip"] == "203.0.113.0"


def test_mobile_signup_returns_a_cookie_free_bearer_session_and_frees_the_email_budget(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    response = auth_harness.client.post(SIGNUP_PATH, json={**SIGNUP_PAYLOAD, "email": " PERSON@example.com "})

    assert response.status_code == 200
    payload = response.json()
    assert payload["credential_transport"] == "body"
    assert payload["access_token"] == ACCESS_SECRET
    assert payload["token_type"] == "Bearer"
    assert payload["expires_in"] == settings.api_key_login_ttl_seconds
    assert response.headers["cache-control"] == "no-store"
    _assert_cookie_free(response)
    assert tarpit_calls == []
    assert auth_harness.login.signup_calls[0][1]["email"] == USER.email
    assert auth_harness.login.signup_calls[0][1]["source"] == "mobile"
    assert ("mobile_auth_email", USER.email) not in auth_harness.rate_limit.attempts
    assert auth_harness.rate_limit.attempts[("mobile_auth_ip", "testclient")] == 1


def test_mobile_signup_rejects_a_duplicate_email_after_the_tarpit(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.reject_signup = True

    response = auth_harness.client.post(SIGNUP_PATH, json=SIGNUP_PAYLOAD)

    assert response.status_code == 400
    assert response.json()["code"] == "email_already_registered"
    assert response.json()["detail"] == "E-mail já cadastrado."
    assert tarpit_calls == [4.0]
    assert auth_harness.rate_limit.attempts[("mobile_auth_email", USER.email)] == 1
    _assert_cookie_free(response)


def test_a_fifth_mobile_signup_for_one_email_is_rate_limited(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.reject_signup = True
    attempts = [
        _client_from(auth_harness, f"198.51.100.{index}").post(SIGNUP_PATH, json=SIGNUP_PAYLOAD) for index in range(4)
    ]

    limited = _client_from(auth_harness, "198.51.100.4").post(SIGNUP_PATH, json=SIGNUP_PAYLOAD)

    assert [response.status_code for response in attempts] == [400] * 4
    assert limited.status_code == 429
    assert limited.json()["code"] == "login_rate_limited"
    assert tarpit_calls == [4.0] * 5
    assert len(auth_harness.login.signup_calls) == 4
    assert _rate_identities(auth_harness, "mobile_auth_email") == [USER.email] * 5


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        (LOGIN_PATH, {"email": "", "password": "password"}),
        (LOGIN_PATH, {"email": USER.email, "password": ""}),
        (LOGIN_PATH, {"email": USER.email}),
        (SIGNUP_PATH, {"email": "", "password": "password"}),
        (SIGNUP_PATH, {"email": USER.email, "password": ""}),
    ],
)
def test_mobile_auth_schema_validation_is_stable(
    auth_harness: AuthHarness,
    path: str,
    payload: dict[str, str],
) -> None:
    response = auth_harness.client.post(path, json=payload)

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert auth_harness.rate_limit.calls == []


def test_mobile_auth_operations_are_published_as_body_transport_in_the_openapi(
    auth_harness: AuthHarness,
) -> None:
    schema = auth_harness.app.openapi()

    login_operation = schema["paths"][LOGIN_PATH]["post"]
    assert {"200", "202", "422"}.issubset(login_operation["responses"])
    assert "auth" in login_operation["tags"]
    assert {"200", "422"}.issubset(schema["paths"][SIGNUP_PATH]["post"]["responses"])
    for name in ("MobileLoginRequest", "MobileSignupRequest"):
        request_schema = schema["components"]["schemas"][name]
        assert request_schema["additionalProperties"] is False
        assert set(request_schema["properties"]) == {"email", "password"}
        assert set(request_schema["required"]) == {"email", "password"}


def test_apple_app_site_association_declares_the_ios_bundle_for_the_team(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "apple_team_id", "ABCDE12345")

    response = TestClient(create_app()).get(AASA_PATH)

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"webcredentials": {"apps": ["ABCDE12345.br.com.rentivo.ios"]}}


def test_apple_app_site_association_is_absent_without_a_configured_team(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "apple_team_id", "")

    response = TestClient(create_app()).get(AASA_PATH)

    assert response.status_code == 404
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "not_found"
