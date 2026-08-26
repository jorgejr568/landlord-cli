from __future__ import annotations

import asyncio
import ipaddress
import json
from datetime import datetime

import structlog
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, Response

from rentivo.api.analytics import analytics_headers, set_analytics
from rentivo.api.authentication import (
    allow_mfa_setup,
    reject_out_of_band_credentials,
)
from rentivo.api.cookies import clear_auth_cookies, client_ip, copy_set_cookies
from rentivo.api.csrf import issue_csrf_token, require_csrf
from rentivo.api.dependencies import get_services, require_login_scope
from rentivo.api.errors import ProblemException, problem
from rentivo.api.principal import Principal
from rentivo.api.schemas.auth import (
    AcceptedResponse,
    AnalyticsEvent,
    AuthConfigResponse,
    AuthenticatedResponse,
    CSRFResponse,
    FeatureFlags,
    LoginRequest,
    MFARequiredResponse,
    MobileAuthorizationExchangeRequest,
    MobileAuthorizationRequest,
    MobileAuthorizationResponse,
    MobileLoginRequest,
    MobileSignupRequest,
    PasswordForgotRequest,
    PasswordResetRequest,
    SessionResponse,
    SignupRequest,
)
from rentivo.api.session_response import login_response, mfa_response, session_response
from rentivo.constants.api_scopes import APIScope
from rentivo.context import ANON_ACTOR, Actor
from rentivo.models.audit_log import AuditEventType
from rentivo.services.container import RequestServices
from rentivo.services.user_service import UserAlreadyRegisteredError
from rentivo.settings import settings

logger = structlog.get_logger(__name__)
router = APIRouter(
    prefix="/auth",
    tags=["auth"],
    dependencies=[Depends(reject_out_of_band_credentials)],
)


def _login_rate_identity(*, email: str, ip: str) -> str:
    return json.dumps((email, ip), separators=(",", ":"))


async def _verify_turnstile(request: Request, services: RequestServices, token: str) -> None:
    if not await services.turnstile.verify(token, client_ip(request)):
        raise ProblemException.bad_request(
            "turnstile_failed",
            "Verificação de segurança falhou. Tente novamente.",
        )


def _audit_login_failure(
    services: RequestServices,
    *,
    email: str,
    ip: str,
    source: str,
) -> None:
    services.audit.safe_log_for(
        Actor(user_id=None, email="", source=source),
        AuditEventType.USER_LOGIN_FAILED,
        entity_type="user",
        new_state={"email": email},
        metadata={"ip": ip},
    )


def _login_failure_problem(*, rate_limited: bool) -> ProblemException:
    if rate_limited:
        value = problem(
            status=429,
            code="login_rate_limited",
            title="Muitas tentativas",
            detail="Muitas tentativas. Aguarde um momento antes de tentar novamente.",
        )
        reason = "rate_limited"
    else:
        value = problem(
            status=401,
            code="invalid_credentials",
            title="Não autenticado",
            detail="E-mail ou senha inválidos.",
        )
        reason = "bad_credentials"
    return ProblemException(value, headers=analytics_headers("rentivo_login_failed", reason=reason))


@router.post("/signup", response_model=AuthenticatedResponse)
async def signup(
    payload: SignupRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    await _verify_turnstile(request, services, payload.turnstile_token)
    try:
        result = services.login.signup(
            email=payload.email,
            password=payload.password,
            client_ip=client_ip(request),
            user_agent=request.headers.get("user-agent", ""),
            source="web" if payload.credential_transport == "cookie" else "mobile",
        )
    except UserAlreadyRegisteredError:
        raise ProblemException.bad_request("email_already_registered", "E-mail já cadastrado.") from None
    return login_response(result, credential_transport=payload.credential_transport)


@router.post(
    "/login",
    response_model=AuthenticatedResponse,
    responses={202: {"model": MFARequiredResponse}},
)
async def login(
    payload: LoginRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    ip = client_ip(request)
    rate_identity = _login_rate_identity(email=payload.email, ip=ip)
    await _verify_turnstile(request, services, payload.turnstile_token)
    if not services.auth_rate_limit.reserve(
        action="login",
        identity=rate_identity,
        limit=5,
        window_seconds=60,
    ):
        raise _login_failure_problem(rate_limited=True)
    try:
        source = "web" if payload.credential_transport == "cookie" else "mobile"
        result = services.login.login(
            email=payload.email,
            password=payload.password,
            client_ip=ip,
            user_agent=request.headers.get("user-agent", ""),
            source=source,
        )
    except ProblemException as exc:
        if exc.problem.code == "invalid_credentials":
            _audit_login_failure(
                services,
                email=payload.email,
                ip=ip,
                source=source,
            )
            raise _login_failure_problem(rate_limited=False) from None
        raise
    if result is None:
        _audit_login_failure(
            services,
            email=payload.email,
            ip=ip,
            source=source,
        )
        raise _login_failure_problem(rate_limited=False)
    services.auth_rate_limit.clear(action="login", identity=rate_identity)
    if result.status == "mfa_required":
        return mfa_response(result, credential_transport=payload.credential_transport)
    return login_response(result, credential_transport=payload.credential_transport)


# Native clients cannot solve the Turnstile widget, so `/auth/mobile/*` trades
# it for two rate-limit budgets plus a fixed-deadline tarpit in front of every
# credential rejection.
#
# * The PRIMARY budget is keyed on the (e-mail, IP) PAIR — the same identity the
#   web `/login` route rate-limits (`_login_rate_identity`). It is charged on
#   every attempt and released on success, and it bounds one account from one
#   client to ~4 tries per minute. Because the key includes both the e-mail and
#   the IP, a flood against a different account, or against the same account
#   from a different IP, lands on a *different* key and can never lock out a
#   legitimate user (invariant A).
# * The BRUTE-FORCE budget is keyed on the client IP and is atomically charged
#   on FAILURE ONLY. The reservation result decides whether that failure is
#   returned as an ordinary credential rejection or a 429. Successful logins
#   neither read nor consume it, so many users sharing one carrier-grade NAT
#   address are never throttled (invariant B); an IP that keeps failing across
#   many accounts is refused once it crosses the looser failure limit.
#
# The delay itself runs in `_MobileAuthTarpitMiddleware` (see app.py), which
# sits OUTSIDE the DB-connection middleware. Handlers only stamp a deadline —
# captured at entry so every rejection returns at the same wall-clock offset
# regardless of how long the credential check took — and return immediately, so
# no pooled connection is ever pinned while the tarpit elapses.
TARPIT_DEADLINE_HEADER = "x-rentivo-tarpit-deadline"
_MOBILE_PAIR_RATE_LIMIT = 4
_MOBILE_IP_FAILURE_LIMIT = 10
_MOBILE_RATE_WINDOW_SECONDS = 60
_MOBILE_FAILURE_DELAY_SECONDS = 4.0
_MOBILE_PAIR_RATE_ACTION = "mobile_auth"
_MOBILE_IP_FAILURE_ACTION = "mobile_auth_ip"


def _mobile_failure_deadline() -> float:
    return asyncio.get_running_loop().time() + _MOBILE_FAILURE_DELAY_SECONDS


def _tarpit(exc: ProblemException, *, deadline: float) -> ProblemException:
    # Mark the failure so the outer tarpit middleware delays it until `deadline`
    # without this handler (and its pooled DB connection) staying on the stack.
    exc.headers[TARPIT_DEADLINE_HEADER] = repr(deadline)
    return exc


def _mobile_ip_identity(ip: str) -> str:
    # Key the per-IP failure budget on the /64 for IPv6 — the smallest block a
    # single client is typically handed and can rotate within for free — and on
    # the exact address for IPv4.
    try:
        address = ipaddress.ip_address(ip)
    except ValueError:
        return ip
    if address.version == 6:
        return str(ipaddress.ip_network(f"{address}/64", strict=False).network_address)
    return str(address)


def _reserve_mobile_attempt(services: RequestServices, *, email: str, ip: str) -> bool:
    # Charge only the (e-mail, IP) pair before authenticating. In particular,
    # do not consult the IP-failure budget here: a correct password must still
    # work behind a noisy carrier-grade NAT address.
    return services.auth_rate_limit.reserve(
        action=_MOBILE_PAIR_RATE_ACTION,
        identity=_login_rate_identity(email=email, ip=ip),
        limit=_MOBILE_PAIR_RATE_LIMIT,
        window_seconds=_MOBILE_RATE_WINDOW_SECONDS,
    )


def _charge_mobile_ip_failure(services: RequestServices, *, ip: str) -> bool:
    # `reserve` is an atomic increment-and-check in the repository. Doing this
    # after failure makes concurrent enforcement race-safe without ever
    # charging or pre-emptively blocking a successful credential check.
    return services.auth_rate_limit.reserve(
        action=_MOBILE_IP_FAILURE_ACTION,
        identity=_mobile_ip_identity(ip),
        limit=_MOBILE_IP_FAILURE_LIMIT,
        window_seconds=_MOBILE_RATE_WINDOW_SECONDS,
    )


def _clear_mobile_pair(services: RequestServices, *, email: str, ip: str) -> None:
    # A success releases only the (e-mail, IP) pair budget. The per-IP failure
    # budget is never touched here, so a legitimate login can neither be blocked
    # by, nor reset, another party's failures from the same address.
    services.auth_rate_limit.clear(
        action=_MOBILE_PAIR_RATE_ACTION,
        identity=_login_rate_identity(email=email, ip=ip),
    )


@router.post("/mobile/signup", response_model=AuthenticatedResponse)
async def mobile_signup(
    payload: MobileSignupRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    deadline = _mobile_failure_deadline()
    ip = client_ip(request)
    if not _reserve_mobile_attempt(services, email=payload.email, ip=ip):
        _charge_mobile_ip_failure(services, ip=ip)
        raise _tarpit(_login_failure_problem(rate_limited=True), deadline=deadline)
    try:
        result = services.login.signup(
            email=payload.email,
            password=payload.password,
            client_ip=ip,
            user_agent=request.headers.get("user-agent", ""),
            source="mobile",
        )
    except UserAlreadyRegisteredError:
        ip_allowed = _charge_mobile_ip_failure(services, ip=ip)
        if not ip_allowed:
            raise _tarpit(_login_failure_problem(rate_limited=True), deadline=deadline) from None
        raise _tarpit(
            ProblemException.bad_request("email_already_registered", "E-mail já cadastrado."),
            deadline=deadline,
        ) from None
    _clear_mobile_pair(services, email=payload.email, ip=ip)
    # Native signup carries no App Attest / Play Integrity attestation — a
    # deliberate product decision — so nothing here proves a real device.
    # Tarpitting the SUCCESS path too is the cheap mitigation against bulk bot
    # account creation and welcome-mail bombing; device attestation is the real
    # fix and is deferred, not forgotten.
    response = login_response(result, credential_transport="body")
    response.headers[TARPIT_DEADLINE_HEADER] = repr(deadline)
    return response


@router.post(
    "/mobile/login",
    response_model=AuthenticatedResponse,
    responses={202: {"model": MFARequiredResponse}},
)
async def mobile_login(
    payload: MobileLoginRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    deadline = _mobile_failure_deadline()
    ip = client_ip(request)
    if not _reserve_mobile_attempt(services, email=payload.email, ip=ip):
        _charge_mobile_ip_failure(services, ip=ip)
        raise _tarpit(_login_failure_problem(rate_limited=True), deadline=deadline)
    try:
        result = services.login.login(
            email=payload.email,
            password=payload.password,
            client_ip=ip,
            user_agent=request.headers.get("user-agent", ""),
            source="mobile",
        )
    except ProblemException as exc:
        if exc.problem.code == "invalid_credentials":
            _audit_login_failure(services, email=payload.email, ip=ip, source="mobile")
            ip_allowed = _charge_mobile_ip_failure(services, ip=ip)
            raise _tarpit(_login_failure_problem(rate_limited=not ip_allowed), deadline=deadline) from None
        raise
    if result is None:
        _audit_login_failure(services, email=payload.email, ip=ip, source="mobile")
        ip_allowed = _charge_mobile_ip_failure(services, ip=ip)
        raise _tarpit(_login_failure_problem(rate_limited=not ip_allowed), deadline=deadline)
    _clear_mobile_pair(services, email=payload.email, ip=ip)
    if result.status == "mfa_required":
        return mfa_response(result, credential_transport="body")
    return login_response(result, credential_transport="body")


_login_principal = require_login_scope(APIScope.PROFILE_READ)


def _invalid_mobile_authorization() -> ProblemException:
    return ProblemException.unauthorized(
        "invalid_or_expired_mobile_authorization",
        "Autorização móvel inválida ou expirada.",
    )


# Legacy browser-handoff path (task U12): `/mobile/authorize` + `/mobile/exchange`
# were how the now-removed native in-app browser login round-tripped a session to
# the app. They are superseded by the direct `/auth/mobile/login` + `/signup`
# credential endpoints and kept only for backward compatibility; behavior is
# unchanged, they are just flagged `deprecated` in the OpenAPI contract.
@router.post(
    "/mobile/authorize",
    response_model=MobileAuthorizationResponse,
    status_code=201,
    deprecated=True,
)
async def authorize_mobile(
    payload: MobileAuthorizationRequest,
    principal: Principal = Depends(_login_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> MobileAuthorizationResponse:
    issued = services.auth_challenge.issue(
        user_id=principal.user.id,
        phase="mobile_authorization",
        allowed_methods=("exchange",),
    )
    return MobileAuthorizationResponse(
        authorization_code=f"{issued.challenge.uuid}.{issued.nonce}", state=payload.state
    )


# Legacy browser-handoff path (task U12): see the note on `authorize_mobile`.
# Superseded by `/auth/mobile/login` + `/signup`; kept for backward
# compatibility, deprecated in the contract, behavior unchanged.
@router.post("/mobile/exchange", response_model=AuthenticatedResponse, deprecated=True)
async def exchange_mobile_authorization(
    payload: MobileAuthorizationExchangeRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    challenge_id, separator, nonce = payload.authorization_code.partition(".")
    if not separator or not challenge_id or not nonce:
        raise _invalid_mobile_authorization()
    challenge = services.auth_challenge.consume(
        challenge_id,
        nonce,
        expected_phase="mobile_authorization",
        expected_method="exchange",
    )
    if challenge is None or challenge.user_id is None:
        raise _invalid_mobile_authorization()
    user = services.user.get_by_id(challenge.user_id)
    if user is None:
        raise _invalid_mobile_authorization()
    result = services.login.complete_login(
        user=user,
        via="mobile_authorization",
        client_ip=client_ip(request),
        user_agent=request.headers.get("user-agent", ""),
        source="mobile",
    )
    return login_response(result, credential_transport="body")


@router.get("/session", response_model=SessionResponse)
async def session(
    _allow_mfa_setup: None = Depends(allow_mfa_setup),
    principal: Principal = Depends(_login_principal),
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    return session_response(principal, services.login.bootstrap(principal))


@router.post("/logout", status_code=204)
async def logout(
    _allow_mfa_setup: None = Depends(allow_mfa_setup),
    principal: Principal = Depends(_login_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> Response:
    services.api_key.logout(principal.api_key)
    services.audit.safe_log_for(
        principal.actor,
        AuditEventType.USER_LOGOUT,
        entity_type="user",
        entity_id=principal.user.id,
    )
    response = Response(status_code=204)
    set_analytics(response, "rentivo_logout")
    clear_auth_cookies(response, include_challenge=False)
    return response


@router.post("/password/forgot", response_model=AcceptedResponse, status_code=202)
async def password_forgot(
    payload: PasswordForgotRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> JSONResponse:
    ip = client_ip(request)
    await _verify_turnstile(request, services, payload.turnstile_token)
    if not services.auth_rate_limit.reserve(
        action="password_reset",
        identity=ip,
        limit=5,
        window_seconds=60,
    ):
        raise ProblemException(
            problem(
                status=429,
                code="password_reset_rate_limited",
                title="Muitas tentativas",
                detail="Muitas tentativas. Aguarde um momento antes de tentar novamente.",
            )
        )
    try:
        services.password_reset.request_reset(payload.email)
    except Exception:
        logger.warning("password_reset_dispatch_failed")
    services.audit.safe_log_for(
        getattr(request.state, "actor", ANON_ACTOR),
        AuditEventType.USER_PASSWORD_RESET_REQUESTED,
        entity_type="user",
        new_state={"email": payload.email},
    )
    response = AcceptedResponse(analytics_events=(AnalyticsEvent(event="rentivo_password_reset_requested"),))
    return JSONResponse(
        response.model_dump(mode="json"),
        status_code=202,
        headers={"Cache-Control": "no-store"},
    )


@router.post("/password/reset", status_code=204)
async def password_reset(
    payload: PasswordResetRequest,
    request: Request,
    services: RequestServices = Depends(get_services),
) -> Response:
    user_id = services.password_reset.consume(payload.token, payload.password)
    if user_id is None:
        raise ProblemException.bad_request(
            "invalid_or_expired_reset_token",
            "Token de redefinição inválido ou expirado.",
        )
    user = services.user.get_by_id(user_id)
    actor = Actor(
        user_id=user_id,
        email="" if user is None else user.email,
        source="web",
    )
    if user is not None:
        try:
            services.job.enqueue_for(
                actor,
                "email.send",
                {
                    "event": "password_reset_completed",
                    "to_email": user.email,
                    "ctx": {
                        "email": user.email,
                        "changed_at": datetime.now().strftime("%d/%m/%Y %H:%M"),
                        "source_ip": client_ip(request),
                    },
                },
            )
        except Exception:
            logger.warning("password_reset_confirmation_dispatch_failed", user_id=user_id)
    services.audit.safe_log_for(
        actor,
        AuditEventType.USER_PASSWORD_RESET_COMPLETED,
        entity_type="user",
        entity_id=user_id,
    )
    response = Response(status_code=204)
    set_analytics(response, "rentivo_password_reset_completed")
    clear_auth_cookies(response, include_challenge=True)
    return response


@router.get("/config", response_model=AuthConfigResponse)
async def auth_config(services: RequestServices = Depends(get_services)) -> AuthConfigResponse:
    turnstile_enabled = services.turnstile.is_enabled
    return AuthConfigResponse(
        feature_flags=FeatureFlags(
            google_auth=services.google_auth.is_enabled,
            turnstile=turnstile_enabled,
            turnstile_site_key=services.turnstile.site_key if turnstile_enabled else "",
        ),
        analytics={"gtm_container_id": settings.gtm_container_id},
    )


@router.get("/csrf", response_model=CSRFResponse)
async def csrf_token(
    _allow_mfa_setup: None = Depends(allow_mfa_setup),
    principal: Principal = Depends(_login_principal),
) -> JSONResponse:
    cookie_response = Response()
    token = issue_csrf_token(cookie_response, principal)
    response = JSONResponse({"csrf_token": token}, headers={"Cache-Control": "no-store"})
    copy_set_cookies(cookie_response, response)
    return response
