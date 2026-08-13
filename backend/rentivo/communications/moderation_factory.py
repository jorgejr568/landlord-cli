import structlog

from rentivo.communications.moderation_base import ModerationBackend
from rentivo.settings import settings

logger = structlog.get_logger(__name__)


def get_moderation_backend() -> ModerationBackend:
    backend = settings.moderation_backend

    if backend == "lexicon":
        from rentivo.communications.moderation_lexicon import LexiconModerationBackend

        logger.info("moderation_backend_selected", backend="lexicon")
        return LexiconModerationBackend()

    if backend == "openrouter":
        from rentivo.communications.moderation_openrouter import OpenRouterModerationBackend

        # The API key is a credential: log the model, never the key.
        logger.info("moderation_backend_selected", backend="openrouter", model=settings.openrouter_model)
        return OpenRouterModerationBackend(
            api_key=settings.openrouter_api_key,
            base_url=settings.openrouter_base_url,
            model=settings.openrouter_model,
            timeout_seconds=settings.moderation_timeout_seconds,
            cache_ttl_seconds=settings.moderation_cache_ttl_seconds,
        )

    raise ValueError(f"Unsupported moderation backend: {backend}")
