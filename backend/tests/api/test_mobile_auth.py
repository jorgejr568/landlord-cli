"""Contract tests for Turnstile-free native auth and the AASA manifest."""

from __future__ import annotations

import asyncio
import time

import pytest
from fastapi.testclient import TestClient

import rentivo.api.app as api_app
import rentivo.api.routes.auth as auth_routes
from rentivo.api.app import create_app
from rentivo.api.authentication import ACCESS_COOKIE_NAME
from rentivo.api.csrf import CSRF_COOKIE_NAME
from rentivo.api.errors import ProblemException
from rentivo.models.audit_log import AuditEventType
from rentivo.settings import settings
from tests.api.routes.test_auth import (
    ACCESS_SECRET,
    AUTHENTICATED_RESULT,
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
    """Collapse only the tarpit's sleep indirection, never asyncio.sleep globally."""
    real_sleep = asyncio.sleep
    calls: list[float] = []

    async def instant_sleep(delay: float) -> None:
        calls.append(delay)
        await real_sleep(0)

    monkeypatch.setattr(api_app, "_tarpit_sleep", instant_sleep)
    return calls


def _assert_cookie_free(response: object) -> None:
    assert response.headers.get_list("set-cookie") == []
    assert ACCESS_COOKIE_NAME not in response.cookies
    assert CSRF_COOKIE_NAME not in response.cookies
    assert settings.challenge_cookie_name not in response.cookies
    assert auth_routes.TARPIT_DEADLINE_HEADER not in response.headers


def _assert_tarpits(calls: list[float], count: int) -> None:
    assert len(calls) == count
    assert all(0 < delay <= 4.0 for delay in calls)


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


def test_mobile_login_never_asks_turnstile_to_verify_anything(auth_harness: AuthHarness) -> None:
    auth_harness.turnstile.allowed = False

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 200


@pytest.mark.parametrize(
    ("extra_field", "value"),
    [("turnstile_token", "ignored"), ("credential_transport", "cookie")],
)
def test_mobile_login_rejects_fields_it_does_not_negotiate(
    auth_harness: AuthHarness,
    extra_field: str,
    value: str,
) -> None:
    response = auth_harness.client.post(LOGIN_PATH, json={**LOGIN_PAYLOAD, extra_field: value})

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert auth_harness.login.login_calls == []


def test_mobile_login_requiring_mfa_returns_body_challenge_without_delay(
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


def test_mobile_login_success_clears_the_pair_and_never_charges_the_ip_budget(
    auth_harness: AuthHarness,
) -> None:
    assert auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD).status_code == 200

    assert auth_harness.rate_limit.attempts == {}
    assert _rate_identities(auth_harness, "mobile_auth") == ['["person@example.com","testclient"]']
    assert _rate_identities(auth_harness, "mobile_auth_ip") == []


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
    _assert_tarpits(tarpit_calls, 2)
    actors = [args[0] for args, _kwargs in auth_harness.audit.calls]
    assert [args[1] for args, _kwargs in auth_harness.audit.calls] == [AuditEventType.USER_LOGIN_FAILED] * 2
    assert [actor.source for actor in actors] == ["mobile", "mobile"]
    assert _rate_identities(auth_harness, "mobile_auth_ip") == ["testclient", "testclient"]
    _assert_cookie_free(unknown)


def test_mobile_login_tarpits_a_none_result_the_same_as_a_raised_rejection(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"
    _assert_tarpits(tarpit_calls, 1)
    assert len(auth_harness.audit.calls) == 1


def test_mobile_login_tarpit_sleeps_only_the_remainder_of_the_entry_deadline(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    original_login = auth_harness.login.login
    auth_harness.login.reject_login = True

    def slow_rejection(*args: object, **kwargs: object) -> object:
        time.sleep(0.05)
        return original_login(*args, **kwargs)

    auth_harness.login.login = slow_rejection

    response = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 401
    assert len(tarpit_calls) == 1
    assert 3.0 < tarpit_calls[0] < 3.98


def test_mobile_login_passes_through_noncredential_problems_without_tarpit(
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


def test_one_account_ip_pair_is_limited_after_four_failures(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None

    attempts = [auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD) for _ in range(4)]
    limited = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert [response.status_code for response in attempts] == [401] * 4
    assert limited.status_code == 429
    assert limited.json()["code"] == "login_rate_limited"
    assert limited.headers["X-Rentivo-Analytics-Reason"] == "rate_limited"
    _assert_tarpits(tarpit_calls, 5)
    assert len(auth_harness.login.login_calls) == 4
    assert len(set(_rate_identities(auth_harness, "mobile_auth"))) == 1
    assert _rate_identities(auth_harness, "mobile_auth_ip") == ["testclient"] * 5


def test_failures_from_another_ip_do_not_block_the_victims_correct_password(
    auth_harness: AuthHarness,
) -> None:
    attacker = _client_from(auth_harness, "203.0.113.10")
    victim = _client_from(auth_harness, "203.0.113.11")
    auth_harness.login.login_result = None
    assert [attacker.post(LOGIN_PATH, json=LOGIN_PAYLOAD).status_code for _ in range(4)] == [401] * 4

    auth_harness.login.login_result = AUTHENTICATED_RESULT
    response = victim.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert response.status_code == 200


def test_noisy_ip_is_limited_only_on_failures_and_can_still_log_in_correctly(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.login_result = None
    failures = [
        auth_harness.client.post(
            LOGIN_PATH,
            json={"email": f"attacker-target-{index}@example.com", "password": "wrong"},
        )
        for index in range(10)
    ]
    limited = auth_harness.client.post(
        LOGIN_PATH,
        json={"email": "eleventh-target@example.com", "password": "wrong"},
    )

    auth_harness.login.login_result = AUTHENTICATED_RESULT
    legitimate = auth_harness.client.post(LOGIN_PATH, json=LOGIN_PAYLOAD)

    assert [response.status_code for response in failures] == [401] * 10
    assert limited.status_code == 429
    assert legitimate.status_code == 200
    _assert_tarpits(tarpit_calls, 11)
    assert _rate_identities(auth_harness, "mobile_auth_ip") == ["testclient"] * 11


def test_many_successful_users_behind_one_ip_never_consume_its_budget(auth_harness: AuthHarness) -> None:
    responses = [
        auth_harness.client.post(
            LOGIN_PATH,
            json={"email": f"nat-user-{index}@example.com", "password": "correct"},
        )
        for index in range(12)
    ]

    assert [response.status_code for response in responses] == [200] * 12
    assert _rate_identities(auth_harness, "mobile_auth_ip") == []
    assert auth_harness.rate_limit.attempts == {}


@pytest.mark.parametrize(
    ("ip", "expected"),
    [
        ("203.0.113.42", "203.0.113.42"),
        ("2001:db8:abcd:12:1111:2222:3333:4444", "2001:db8:abcd:12::"),
        ("testclient", "testclient"),
    ],
)
def test_mobile_ip_budget_normalizes_ipv6_to_64(ip: str, expected: str) -> None:
    assert auth_routes._mobile_ip_identity(ip) == expected


def test_mobile_signup_returns_a_cookie_free_bearer_session_after_tarpit(
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
    _assert_tarpits(tarpit_calls, 1)
    assert auth_harness.login.signup_calls[0][1]["email"] == USER.email
    assert auth_harness.login.signup_calls[0][1]["source"] == "mobile"
    assert auth_harness.rate_limit.attempts == {}
    assert _rate_identities(auth_harness, "mobile_auth_ip") == []


def test_mobile_signup_rejects_a_duplicate_email_after_the_tarpit(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.reject_signup = True

    response = auth_harness.client.post(SIGNUP_PATH, json=SIGNUP_PAYLOAD)

    assert response.status_code == 400
    assert response.json()["code"] == "email_already_registered"
    assert response.json()["detail"] == "E-mail já cadastrado."
    _assert_tarpits(tarpit_calls, 1)
    assert auth_harness.rate_limit.attempts[("mobile_auth_ip", "testclient")] == 1
    _assert_cookie_free(response)


def test_mobile_signup_uses_the_same_pair_and_failure_only_ip_budgets(
    auth_harness: AuthHarness,
    tarpit_calls: list[float],
) -> None:
    auth_harness.login.reject_signup = True
    duplicate_attempts = [auth_harness.client.post(SIGNUP_PATH, json=SIGNUP_PAYLOAD) for _ in range(4)]
    pair_limited = auth_harness.client.post(SIGNUP_PATH, json=SIGNUP_PAYLOAD)

    assert [response.status_code for response in duplicate_attempts] == [400] * 4
    assert pair_limited.status_code == 429
    assert len(auth_harness.login.signup_calls) == 4
    assert _rate_identities(auth_harness, "mobile_auth_ip") == ["testclient"] * 5
    _assert_tarpits(tarpit_calls, 5)


def test_mobile_signup_success_is_not_blocked_by_other_accounts_failures(
    auth_harness: AuthHarness,
) -> None:
    auth_harness.login.reject_signup = True
    for index in range(11):
        auth_harness.client.post(
            SIGNUP_PATH,
            json={"email": f"duplicate-{index}@example.com", "password": "password"},
        )

    auth_harness.login.reject_signup = False
    response = auth_harness.client.post(SIGNUP_PATH, json=SIGNUP_PAYLOAD)

    assert response.status_code == 200


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


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        (LOGIN_PATH, {"email": USER.email, "password": "á" * 37}),
        (SIGNUP_PATH, {"email": USER.email, "password": "á" * 37}),
        (
            "/api/v1/auth/login",
            {"email": USER.email, "password": "á" * 37, "turnstile_token": "token"},
        ),
        (
            "/api/v1/auth/signup",
            {
                "email": USER.email,
                "password": "á" * 37,
                "confirm_password": "á" * 37,
                "turnstile_token": "token",
            },
        ),
    ],
)
def test_auth_passwords_over_72_utf8_bytes_return_422_before_services(
    auth_harness: AuthHarness,
    path: str,
    payload: dict[str, str],
) -> None:
    response = auth_harness.client.post(path, json=payload)

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert "Senha muito longa" in str(response.json()["fields"])
    assert auth_harness.login.login_calls == []
    assert auth_harness.login.signup_calls == []
    assert auth_harness.rate_limit.calls == []


def test_mobile_auth_openapi_describes_body_transport_limits_and_legacy_deprecation(
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
        assert request_schema["properties"]["password"]["maxLength"] == 72
        assert set(request_schema["required"]) == {"email", "password"}
    assert schema["paths"]["/api/v1/auth/mobile/authorize"]["post"]["deprecated"] is True
    assert schema["paths"]["/api/v1/auth/mobile/exchange"]["post"]["deprecated"] is True


def test_apple_app_site_association_declares_the_ios_bundle_with_short_cache(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "apple_team_id", "ABCDE12345")

    response = TestClient(create_app()).get(AASA_PATH)

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.headers["cache-control"] == "public, max-age=300"
    assert response.json() == {"webcredentials": {"apps": ["ABCDE12345.br.com.rentivo.ios"]}}


def test_apple_app_site_association_is_absent_without_a_configured_team(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "apple_team_id", "")

    response = TestClient(create_app()).get(AASA_PATH)

    assert response.status_code == 404
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["code"] == "not_found"
