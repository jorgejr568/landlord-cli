from __future__ import annotations

from datetime import datetime, timezone
from xml.sax.saxutils import escape

from fastapi import APIRouter, Request
from sqlalchemy import text
from starlette.responses import JSONResponse, Response

from rentivo import db
from rentivo.api.errors import ProblemException, problem
from rentivo.origins import parse_public_origin as _parse_public_origin
from rentivo.settings import settings

router = APIRouter()

PUBLIC_PATHS: tuple[str, ...] = ("/", "/login", "/signup")
DISALLOWED_PATHS: tuple[str, ...] = (
    "/billings/",
    "/organizations/",
    "/invites/",
    "/themes/",
    "/security",
    "/change-password",
    "/logout",
    "/mfa-verify",
)
IOS_BUNDLE_ID = "br.com.rentivo.ios"
AI_CRAWLERS: tuple[str, ...] = (
    "GPTBot",
    "ChatGPT-User",
    "OAI-SearchBot",
    "ClaudeBot",
    "Claude-Web",
    "anthropic-ai",
    "PerplexityBot",
    "Perplexity-User",
    "Google-Extended",
    "Applebot-Extended",
    "Bytespider",
    "CCBot",
    "cohere-ai",
    "Meta-ExternalAgent",
    "Meta-ExternalFetcher",
    "Amazonbot",
    "DuckAssistBot",
    "Diffbot",
    "YouBot",
)


def _public_origin(request: Request) -> str:
    if settings.public_url:
        configured_origin = _parse_public_origin(settings.public_url, allow_localhost=False)
        if configured_origin is None:
            raise ProblemException(
                problem(
                    status=500,
                    code="invalid_public_origin",
                    title="Configuração inválida",
                    detail="A origem pública configurada é inválida.",
                )
            )
        return configured_origin
    if settings.environment == "production":
        raise ProblemException(
            problem(
                status=500,
                code="public_origin_not_configured",
                title="Configuração inválida",
                detail="A origem pública precisa ser configurada em produção.",
            )
        )
    request_origin = _parse_public_origin(f"{request.url.scheme}://{request.url.netloc}", allow_localhost=True)
    if request_origin is None:
        raise ProblemException.bad_request("invalid_public_origin", "A origem pública da requisição é inválida.")
    return request_origin


def _rules_block(user_agent: str) -> list[str]:
    return [
        f"User-agent: {user_agent}",
        *(f"Allow: {path}" for path in PUBLIC_PATHS),
        *(f"Disallow: {path}" for path in DISALLOWED_PATHS),
    ]


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/api/v1/ready")
async def ready() -> dict[str, str]:
    try:
        with db.get_engine().connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception:
        raise ProblemException(
            problem(
                status=503,
                code="not_ready",
                title="Serviço indisponível",
                detail="O banco de dados não está disponível.",
            )
        ) from None
    return {"status": "ready"}


@router.get("/.well-known/apple-app-site-association")
async def apple_app_site_association() -> Response:
    """Associated-domains manifest that lets the iOS app reuse the site's passkeys.

    Served at the document root (not under ``/api``) because that is the only
    place iOS looks. Without a configured team ID there is nothing truthful to
    publish, so the path simply does not exist.
    """
    if not settings.apple_team_id:
        raise ProblemException.not_found()
    # This document is not under ``/api`` so ``_APINoStoreMiddleware`` never
    # touches it. iOS re-fetches it rarely and it changes only when the team ID
    # changes, so a short shared cache lifetime is safe and avoids hammering the
    # origin on every associated-domains check.
    return JSONResponse(
        {"webcredentials": {"apps": [f"{settings.apple_team_id}.{IOS_BUNDLE_ID}"]}},
        headers={"Cache-Control": "public, max-age=300"},
    )


@router.get("/.well-known/assetlinks.json")
async def android_asset_links() -> Response:
    """Digital Asset Links manifest that associates the site with the Android app.

    Served at the document root (not under ``/api``) because that is the only
    place Android Credential Manager and password managers look. Without a
    configured signing-cert fingerprint there is nothing truthful to publish, so
    the path simply does not exist.
    """
    fingerprints = settings.android_cert_fingerprint_list
    if not fingerprints:
        raise ProblemException.not_found()
    # Like the AASA manifest this lives outside ``/api`` so the no-store
    # middleware never touches it. It changes only when the package or signing
    # certificate changes, so a short shared cache lifetime is safe.
    return JSONResponse(
        [
            {
                "relation": ["delegate_permission/common.get_login_creds"],
                "target": {
                    "namespace": "android_app",
                    "package_name": settings.android_package_name,
                    "sha256_cert_fingerprints": fingerprints,
                },
            }
        ],
        headers={"Cache-Control": "public, max-age=300"},
    )


@router.get("/robots.txt")
async def robots_txt(request: Request) -> Response:
    blocks = [_rules_block("*"), *(_rules_block(agent) for agent in AI_CRAWLERS)]
    body = "\n\n".join("\n".join(block) for block in blocks)
    body += f"\n\nSitemap: {_public_origin(request)}/sitemap.xml\n"
    return Response(content=body, media_type="text/plain")


@router.get("/sitemap.xml")
async def sitemap_xml(request: Request) -> Response:
    base = _public_origin(request)
    lastmod = datetime.now(timezone.utc).date().isoformat()
    entries = []
    for path in PUBLIC_PATHS:
        priority = "1.0" if path == "/" else "0.7"
        entries.append(
            "  <url>\n"
            f"    <loc>{escape(f'{base}{path}')}</loc>\n"
            f"    <lastmod>{lastmod}</lastmod>\n"
            "    <changefreq>monthly</changefreq>\n"
            f"    <priority>{priority}</priority>\n"
            "  </url>"
        )
    body = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + "\n".join(entries) + "\n</urlset>\n"
    )
    return Response(content=body, media_type="application/xml")
