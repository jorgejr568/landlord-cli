from __future__ import annotations

import asyncio
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from threading import Event

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

import rentivo.api.app as api_app
from rentivo.api.app import create_app
from rentivo.models.audit_log import AuditEventType
from tests.conftest import SCHEMA_DDL

LOGIN_PATH = "/api/v1/auth/mobile/login"
SIGNUP_PATH = "/api/v1/auth/mobile/signup"
PASSWORD = "correct horse battery staple"

_NATIVE_AUTH_SCHEMA = (
    """
    CREATE TABLE api_keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid VARCHAR(26) NOT NULL,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        secret_hash BINARY(32) NOT NULL,
        key_start VARCHAR(4) NOT NULL,
        key_end VARCHAR(2) NOT NULL,
        is_login_token BOOLEAN NOT NULL DEFAULT 0,
        expires_at DATETIME NOT NULL,
        last_used_at DATETIME,
        created_at DATETIME NOT NULL,
        revoked_at DATETIME
    )
    """,
    "CREATE UNIQUE INDEX ix_api_keys_uuid ON api_keys (uuid)",
    "CREATE UNIQUE INDEX ix_api_keys_secret_hash ON api_keys (secret_hash)",
    "CREATE INDEX ix_api_keys_user_id ON api_keys (user_id)",
    "CREATE INDEX ix_api_keys_expires_at ON api_keys (expires_at)",
    "CREATE INDEX ix_api_keys_revoked_at ON api_keys (revoked_at)",
    """
    CREATE TABLE api_key_scopes (
        api_key_id INTEGER NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
        scope VARCHAR(64) NOT NULL,
        PRIMARY KEY (api_key_id, scope)
    )
    """,
    """
    CREATE TABLE api_key_resource_grants (
        api_key_id INTEGER NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
        resource_type VARCHAR(20) NOT NULL,
        resource_id INTEGER NOT NULL,
        CHECK (resource_type IN ('user', 'organization')),
        PRIMARY KEY (api_key_id, resource_type, resource_id)
    )
    """,
    """
    CREATE TABLE auth_rate_limits (
        action VARCHAR(32) NOT NULL,
        identity_hash BINARY(32) NOT NULL,
        attempts INTEGER NOT NULL,
        window_started_at DATETIME NOT NULL,
        expires_at DATETIME NOT NULL,
        PRIMARY KEY (action, identity_hash)
    )
    """,
    "CREATE INDEX ix_auth_rate_limits_expires_at ON auth_rate_limits (expires_at)",
)


@dataclass(slots=True)
class NativeAuthHarness:
    app: FastAPI
    client: TestClient
    engine: Engine
    tarpit_calls: list[float]


def _create_schema(engine: Engine) -> None:
    with engine.begin() as connection:
        for statement in SCHEMA_DDL.strip().split(";"):
            if statement.strip():
                connection.execute(text(statement))
        for statement in _NATIVE_AUTH_SCHEMA:
            connection.execute(text(statement))


@pytest.fixture()
def native_auth_harness(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    fake_encryption: object,
) -> Iterator[NativeAuthHarness]:
    engine = create_engine(f"sqlite:///{tmp_path / 'mobile-auth.db'}")
    _create_schema(engine)
    monkeypatch.setattr(api_app, "get_engine", lambda: engine)
    monkeypatch.setattr(api_app, "get_encryption", lambda: fake_encryption)
    real_sleep = asyncio.sleep
    tarpit_calls: list[float] = []

    async def instant_tarpit(delay: float) -> None:
        tarpit_calls.append(delay)
        await real_sleep(0)

    monkeypatch.setattr(api_app, "_tarpit_sleep", instant_tarpit)
    app = create_app()
    with TestClient(app) as client:
        yield NativeAuthHarness(app=app, client=client, engine=engine, tarpit_calls=tarpit_calls)
    engine.dispose()


def _signup(client: TestClient, email: str, password: str = PASSWORD) -> None:
    response = client.post(SIGNUP_PATH, json={"email": email, "password": password})
    assert response.status_code == 200, response.text


def _client_from(harness: NativeAuthHarness, ip: str) -> TestClient:
    return TestClient(harness.app, client=(ip, 50000))


def test_real_bcrypt_mobile_login_succeeds(native_auth_harness: NativeAuthHarness) -> None:
    _signup(native_auth_harness.client, "bcrypt@example.com")
    native_auth_harness.tarpit_calls.clear()

    response = native_auth_harness.client.post(
        LOGIN_PATH,
        json={"email": "bcrypt@example.com", "password": PASSWORD},
    )

    assert response.status_code == 200
    assert response.json()["access_token"].startswith("rntv-v1-")
    assert response.json()["credential_transport"] == "body"
    assert native_auth_harness.tarpit_calls == []
    with native_auth_harness.engine.connect() as connection:
        password_hash = connection.execute(text("SELECT password_hash FROM users")).scalar_one()
    assert password_hash.startswith("$2")
    assert PASSWORD not in password_hash


def test_real_wrong_password_is_tarpitted_and_audited(native_auth_harness: NativeAuthHarness) -> None:
    _signup(native_auth_harness.client, "wrong-password@example.com")
    native_auth_harness.tarpit_calls.clear()

    response = native_auth_harness.client.post(
        LOGIN_PATH,
        json={"email": "wrong-password@example.com", "password": "wrong"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"
    assert len(native_auth_harness.tarpit_calls) == 1
    assert 0 < native_auth_harness.tarpit_calls[0] < 4.0
    with native_auth_harness.engine.connect() as connection:
        audit = (
            connection.execute(text("SELECT event_type, source, metadata FROM audit_logs ORDER BY id DESC LIMIT 1"))
            .mappings()
            .one()
        )
    assert audit["event_type"] == AuditEventType.USER_LOGIN_FAILED
    assert audit["source"] == "mobile"
    assert "wrong-password@example.com" not in str(audit["metadata"])


def test_oversized_mobile_password_is_the_same_422_for_known_and_unknown_accounts(
    native_auth_harness: NativeAuthHarness,
) -> None:
    _signup(native_auth_harness.client, "known@example.com")
    native_auth_harness.tarpit_calls.clear()
    oversized = "x" * 73
    with native_auth_harness.engine.connect() as connection:
        audit_count_before = connection.execute(text("SELECT COUNT(*) FROM audit_logs")).scalar_one()

    responses = [
        native_auth_harness.client.post(LOGIN_PATH, json={"email": email, "password": oversized})
        for email in ("known@example.com", "unknown@example.com")
    ]

    assert [response.status_code for response in responses] == [422, 422]
    assert [response.json()["code"] for response in responses] == ["validation_error"] * 2
    assert native_auth_harness.tarpit_calls == []
    with native_auth_harness.engine.connect() as connection:
        assert connection.execute(text("SELECT COUNT(*) FROM audit_logs")).scalar_one() == audit_count_before
        assert connection.execute(text("SELECT COUNT(*) FROM auth_rate_limits")).scalar_one() == 0


def test_attacker_on_another_ip_cannot_lock_out_the_victims_correct_password(
    native_auth_harness: NativeAuthHarness,
) -> None:
    _signup(native_auth_harness.client, "victim@example.com")
    attacker = _client_from(native_auth_harness, "203.0.113.20")
    victim = _client_from(native_auth_harness, "203.0.113.21")

    failures = [attacker.post(LOGIN_PATH, json={"email": "victim@example.com", "password": "wrong"}) for _ in range(4)]
    legitimate = victim.post(LOGIN_PATH, json={"email": "victim@example.com", "password": PASSWORD})

    assert [response.status_code for response in failures] == [401] * 4
    assert legitimate.status_code == 200


def test_noisy_nat_neighbours_cannot_block_a_correct_password(native_auth_harness: NativeAuthHarness) -> None:
    _signup(native_auth_harness.client, "nat-victim@example.com")
    shared_ip = _client_from(native_auth_harness, "198.51.100.50")

    failures = [
        shared_ip.post(
            LOGIN_PATH,
            json={"email": f"target-{index}@example.com", "password": "wrong"},
        )
        for index in range(10)
    ]
    limited = shared_ip.post(
        LOGIN_PATH,
        json={"email": "target-10@example.com", "password": "wrong"},
    )
    legitimate = shared_ip.post(
        LOGIN_PATH,
        json={"email": "nat-victim@example.com", "password": PASSWORD},
    )

    assert [response.status_code for response in failures] == [401] * 10
    assert limited.status_code == 429
    assert legitimate.status_code == 200


def test_more_than_ten_real_users_behind_one_ip_all_succeed(native_auth_harness: NativeAuthHarness) -> None:
    emails = [f"real-nat-user-{index}@example.com" for index in range(11)]
    for email in emails:
        _signup(native_auth_harness.client, email)
    shared_ip = _client_from(native_auth_harness, "192.0.2.44")

    responses = [shared_ip.post(LOGIN_PATH, json={"email": email, "password": PASSWORD}) for email in emails]

    assert [response.status_code for response in responses] == [200] * 11
    with native_auth_harness.engine.connect() as connection:
        ip_failure_rows = connection.execute(
            text("SELECT COUNT(*) FROM auth_rate_limits WHERE action = 'mobile_auth_ip'")
        ).scalar_one()
    assert ip_failure_rows == 0


def test_tarpit_waits_only_after_the_request_connection_is_returned_to_the_pool(
    native_auth_harness: NativeAuthHarness,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _signup(native_auth_harness.client, "pool@example.com")
    sleep_started = Event()
    release_sleep = Event()
    observed_checked_out: list[int] = []

    async def pending_tarpit(_delay: float) -> None:
        observed_checked_out.append(native_auth_harness.engine.pool.checkedout())
        sleep_started.set()
        while not release_sleep.is_set():
            await asyncio.sleep(0.001)

    monkeypatch.setattr(api_app, "_tarpit_sleep", pending_tarpit)

    with ThreadPoolExecutor(max_workers=1) as executor:
        pending_response = executor.submit(
            native_auth_harness.client.post,
            LOGIN_PATH,
            json={"email": "pool@example.com", "password": "wrong"},
        )
        assert sleep_started.wait(timeout=5)
        assert native_auth_harness.engine.pool.checkedout() == 0
        release_sleep.set()
        response = pending_response.result(timeout=5)

    assert response.status_code == 401
    assert observed_checked_out == [0]
