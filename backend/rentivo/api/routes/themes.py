from __future__ import annotations

from dataclasses import dataclass

from fastapi import APIRouter, Depends, Path, Response

from rentivo.api.csrf import require_csrf
from rentivo.api.dependencies import get_services, require_resource_grant, require_scope
from rentivo.api.domain_access import require_role, resolve_billing_access, resolve_organization_access
from rentivo.api.errors import ProblemException
from rentivo.api.principal import Principal
from rentivo.api.schemas.themes import (
    ThemeCapabilitiesResponse,
    ThemeOptionsResponse,
    ThemeResponse,
    ThemeUpdateRequest,
    ThemeValuesResponse,
)
from rentivo.constants.api_scopes import APIScope
from rentivo.models.audit_log import AuditEventType
from rentivo.models.billing import Billing
from rentivo.models.theme import DEFAULT_THEME, Theme
from rentivo.services.audit_serializers import serialize_theme
from rentivo.services.container import RequestServices

router = APIRouter(prefix="/themes", tags=["themes"])
_read_principal = require_scope(APIScope.THEMES_READ)
_write_principal = require_scope(APIScope.THEMES_WRITE)
_THEME_ADMIN_ROLES = frozenset({"owner", "admin"})
_ANALYTICS_EVENT_HEADER = "X-Rentivo-Analytics-Event"
_ANALYTICS_SCOPE_HEADER = "X-Rentivo-Analytics-Scope"


@dataclass(frozen=True, slots=True)
class ThemeTarget:
    """Authorized theme owner: identity, display name, and the billing to inherit from."""

    owner_type: str
    owner_id: int
    owner_name: str
    billing: Billing | None = None


def _values(theme: Theme) -> ThemeValuesResponse:
    return ThemeValuesResponse(
        header_font=theme.header_font,
        text_font=theme.text_font,
        primary=theme.primary,
        primary_light=theme.primary_light,
        secondary=theme.secondary,
        secondary_dark=theme.secondary_dark,
        text_color=theme.text_color,
        text_contrast=theme.text_contrast,
    )


def _response(
    owner_name: str,
    stored: Theme | None,
    effective: Theme,
    source: str,
    *,
    can_edit: bool,
) -> ThemeResponse:
    return ThemeResponse(
        owner_name=owner_name,
        stored=_values(stored) if stored is not None else None,
        effective=_values(effective),
        effective_source=source,
        options=ThemeOptionsResponse(),
        capabilities=ThemeCapabilitiesResponse(
            can_edit=can_edit,
            can_reset=stored is not None and can_edit,
        ),
    )


def _can_edit(principal: Principal) -> bool:
    return APIScope.THEMES_WRITE.value in principal.api_key.scopes


def _set_theme_analytics(response: Response, scope: str) -> None:
    response.headers[_ANALYTICS_EVENT_HEADER] = "rentivo_theme_changed"
    response.headers[_ANALYTICS_SCOPE_HEADER] = scope


def _persisted_id(entity_id: int | None) -> int:
    """Narrow an identifier that the access resolvers already guarantee is persisted."""
    if entity_id is None:  # pragma: no cover - resolvers reject entities without an id
        raise ProblemException.not_found()
    return entity_id


def _require_user_access(principal: Principal, services: RequestServices) -> ThemeTarget:
    user_id = _persisted_id(principal.user.id)
    require_resource_grant(principal, services, "user", user_id)
    return ThemeTarget(owner_type="user", owner_id=user_id, owner_name="Meu Tema")


def _require_organization_admin(
    principal: Principal,
    services: RequestServices,
    org_uuid: str,
) -> ThemeTarget:
    access = resolve_organization_access(principal, services, org_uuid)
    require_role(access.role, {"admin"})
    return ThemeTarget(
        owner_type="organization",
        owner_id=_persisted_id(access.organization.id),
        owner_name=access.organization.name,
    )


def _require_billing_admin(
    principal: Principal,
    services: RequestServices,
    billing_uuid: str,
) -> ThemeTarget:
    access = resolve_billing_access(principal, services, billing_uuid)
    require_role(access.role, _THEME_ADMIN_ROLES)
    return ThemeTarget(
        owner_type="billing",
        owner_id=_persisted_id(access.billing.id),
        owner_name=access.billing.name,
        billing=access.billing,
    )


def _theme_response(
    services: RequestServices,
    target: ThemeTarget,
    *,
    can_edit: bool,
) -> ThemeResponse:
    stored = services.theme.get_theme_for_owner(target.owner_type, target.owner_id)
    if target.billing is not None:
        resolved = services.theme.resolve_theme_with_source(target.billing)
        return _response(target.owner_name, stored, resolved.theme, resolved.source, can_edit=can_edit)
    effective = stored if stored is not None else DEFAULT_THEME
    source = target.owner_type if stored is not None else "default"
    return _response(target.owner_name, stored, effective, source, can_edit=can_edit)


def _save_theme(
    *,
    services: RequestServices,
    principal: Principal,
    owner_type: str,
    owner_id: int,
    payload: ThemeUpdateRequest,
) -> Theme:
    existing = services.theme.get_theme_for_owner(owner_type, owner_id)
    previous_state = serialize_theme(existing) if existing is not None else None
    saved = services.theme.create_or_update_theme(owner_type, owner_id, **payload.model_dump())
    audit_kwargs: dict[str, object] = {
        "entity_type": "theme",
        "entity_id": saved.id,
        "entity_uuid": saved.uuid,
        "new_state": serialize_theme(saved),
    }
    event_type = AuditEventType.THEME_CREATE
    if previous_state is not None:
        event_type = AuditEventType.THEME_UPDATE
        audit_kwargs["previous_state"] = previous_state
    services.audit.safe_log_for(principal.actor, event_type, **audit_kwargs)
    return saved


def _reset_theme(
    *,
    services: RequestServices,
    principal: Principal,
    owner_type: str,
    owner_id: int,
) -> None:
    existing = services.theme.get_theme_for_owner(owner_type, owner_id)
    if existing is not None and services.theme.delete_theme(owner_type, owner_id):
        services.audit.safe_log_for(
            principal.actor,
            AuditEventType.THEME_DELETE,
            entity_type="theme",
            entity_id=existing.id,
            entity_uuid=existing.uuid,
            previous_state=serialize_theme(existing),
        )


@router.get("/user", response_model=ThemeResponse)
async def get_user_theme(
    principal: Principal = Depends(_read_principal),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_user_access(principal, services)
    return _theme_response(services, target, can_edit=_can_edit(principal))


@router.put("/user", response_model=ThemeResponse)
async def update_user_theme(
    payload: ThemeUpdateRequest,
    response: Response,
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_user_access(principal, services)
    saved = _save_theme(
        services=services,
        principal=principal,
        owner_type=target.owner_type,
        owner_id=target.owner_id,
        payload=payload,
    )
    _set_theme_analytics(response, target.owner_type)
    return _response(target.owner_name, saved, saved, target.owner_type, can_edit=_can_edit(principal))


@router.delete("/user", status_code=204)
async def reset_user_theme(
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> Response:
    target = _require_user_access(principal, services)
    _reset_theme(services=services, principal=principal, owner_type=target.owner_type, owner_id=target.owner_id)
    return Response(status_code=204)


@router.get("/organizations/{org_uuid}", response_model=ThemeResponse)
async def get_organization_theme(
    org_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_read_principal),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_organization_admin(principal, services, org_uuid)
    return _theme_response(services, target, can_edit=_can_edit(principal))


@router.put("/organizations/{org_uuid}", response_model=ThemeResponse)
async def update_organization_theme(
    payload: ThemeUpdateRequest,
    response: Response,
    org_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_organization_admin(principal, services, org_uuid)
    saved = _save_theme(
        services=services,
        principal=principal,
        owner_type=target.owner_type,
        owner_id=target.owner_id,
        payload=payload,
    )
    _set_theme_analytics(response, target.owner_type)
    return _response(target.owner_name, saved, saved, target.owner_type, can_edit=_can_edit(principal))


@router.delete("/organizations/{org_uuid}", status_code=204)
async def reset_organization_theme(
    org_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> Response:
    target = _require_organization_admin(principal, services, org_uuid)
    _reset_theme(services=services, principal=principal, owner_type=target.owner_type, owner_id=target.owner_id)
    return Response(status_code=204)


@router.get("/billings/{billing_uuid}", response_model=ThemeResponse)
async def get_billing_theme(
    billing_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_read_principal),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_billing_admin(principal, services, billing_uuid)
    return _theme_response(services, target, can_edit=_can_edit(principal))


@router.put("/billings/{billing_uuid}", response_model=ThemeResponse)
async def update_billing_theme(
    payload: ThemeUpdateRequest,
    response: Response,
    billing_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> ThemeResponse:
    target = _require_billing_admin(principal, services, billing_uuid)
    saved = _save_theme(
        services=services,
        principal=principal,
        owner_type=target.owner_type,
        owner_id=target.owner_id,
        payload=payload,
    )
    _set_theme_analytics(response, target.owner_type)
    return _response(target.owner_name, saved, saved, target.owner_type, can_edit=_can_edit(principal))


@router.delete("/billings/{billing_uuid}", status_code=204)
async def reset_billing_theme(
    billing_uuid: str = Path(min_length=1),
    principal: Principal = Depends(_write_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> Response:
    target = _require_billing_admin(principal, services, billing_uuid)
    _reset_theme(services=services, principal=principal, owner_type=target.owner_type, owner_id=target.owner_id)
    return Response(status_code=204)


@router.post(
    "/preview",
    response_class=Response,
    responses={
        200: {
            "content": {
                "application/pdf": {
                    "schema": {"type": "string", "format": "binary"},
                }
            }
        }
    },
)
def preview_theme(
    payload: ThemeUpdateRequest,
    _principal: Principal = Depends(_read_principal),
    _csrf: None = Depends(require_csrf),
    services: RequestServices = Depends(get_services),
) -> Response:
    theme = Theme(**payload.model_dump())
    pdf_bytes = services.theme.render_preview(theme)
    return Response(
        content=bytes(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Cache-Control": "no-store",
            "Content-Disposition": 'inline; filename="theme-preview.pdf"',
        },
    )
