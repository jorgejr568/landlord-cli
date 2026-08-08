from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from rentivo.constants.api_scopes import APIScope
from rentivo.context import Actor
from rentivo.models.api_key import APIKey
from rentivo.models.user import User


@dataclass(frozen=True, slots=True)
class Principal:
    user: User
    api_key: APIKey
    source: Literal["web", "mobile", "integration"]

    def has_scope(self, scope: APIScope) -> bool:
        return scope.value in self.api_key.scopes

    @property
    def actor(self) -> Actor:
        return Actor(
            user_id=self.user.id,
            email=self.user.email,
            source=self.source,
            api_key_uuid=self.api_key.uuid,
            is_login_token=self.api_key.is_login_token,
        )
