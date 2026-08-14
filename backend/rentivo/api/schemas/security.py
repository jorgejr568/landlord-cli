from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

from rentivo.api.schemas.auth import BcryptPassword, WebAuthnCredentialDescriptor, WebAuthnModel
from rentivo.pix import normalize_pix_triple


class _StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ProfileResponse(_StrictModel):
    email: str
    pix_key: str | None = ""
    pix_merchant_name: str | None = Field(default="", max_length=25)
    pix_merchant_city: str | None = Field(default="", max_length=15)


class CurrentProfileResponse(_StrictModel):
    email: str


class PixUpdateRequest(_StrictModel):
    pix_key: str | None = ""
    pix_merchant_name: str | None = Field(default="", max_length=25)
    pix_merchant_city: str | None = Field(default="", max_length=15)

    @model_validator(mode="after")
    def normalized_triple(self) -> PixUpdateRequest:
        try:
            self.pix_key, self.pix_merchant_name, self.pix_merchant_city = normalize_pix_triple(
                self.pix_key,
                self.pix_merchant_name,
                self.pix_merchant_city,
            )
        except ValueError as exc:
            raise ValidationError.from_exception_data(
                type(self).__name__,
                [
                    {
                        "type": "value_error",
                        "loc": (field,),
                        "input": getattr(self, field),
                        "ctx": {"error": exc},
                    }
                    for field in ("pix_key", "pix_merchant_name", "pix_merchant_city")
                    if not getattr(self, field)
                ],
            ) from None
        return self


class PixUpdateResponse(_StrictModel):
    profile: ProfileResponse


class PasswordChangeRequest(_StrictModel):
    current_password: BcryptPassword
    new_password: BcryptPassword
    confirm_password: BcryptPassword


class TOTPStatusResponse(_StrictModel):
    enabled: bool
    recovery_codes_remaining: int = Field(ge=0)


class MFAStatusResponse(_StrictModel):
    setup_required: bool
    organization_enforced: bool


class PasskeyResponse(_StrictModel):
    uuid: str
    name: str
    created_at: datetime
    last_used_at: datetime | None = None


class PasskeyListResponse(_StrictModel):
    items: tuple[PasskeyResponse, ...]


class SecuritySummaryResponse(_StrictModel):
    profile: ProfileResponse
    totp: TOTPStatusResponse
    mfa: MFAStatusResponse
    passkeys: tuple[PasskeyResponse, ...]


class TOTPSetupResponse(_StrictModel):
    secret: str
    provisioning_uri: str
    qr_code_base64: str


class TOTPConfirmRequest(_StrictModel):
    code: str = Field(min_length=1)


class TOTPDisableRequest(_StrictModel):
    password: BcryptPassword


class AccountDeleteRequest(_StrictModel):
    password: BcryptPassword


class AccountDeletionReadinessResponse(_StrictModel):
    can_delete: bool
    reason: Literal["sole_organization_admin"] | None = None


class RecoveryCodesResponse(_StrictModel):
    recovery_codes: tuple[str, ...]


class WebAuthnRelyingPartyEntity(WebAuthnModel):
    id: str | None = Field(default=None, min_length=1)
    name: str = Field(min_length=1)


class WebAuthnUserEntity(WebAuthnModel):
    id: str = Field(min_length=1)
    name: str = Field(min_length=1)
    display_name: str = Field(alias="displayName", min_length=1)


class WebAuthnCredentialParameter(WebAuthnModel):
    type: Literal["public-key"]
    alg: int


class WebAuthnAuthenticatorSelection(WebAuthnModel):
    authenticator_attachment: Literal["cross-platform", "platform"] | None = Field(
        default=None,
        alias="authenticatorAttachment",
    )
    resident_key: Literal["discouraged", "preferred", "required"] | None = Field(
        default=None,
        alias="residentKey",
    )
    require_resident_key: bool | None = Field(default=None, alias="requireResidentKey")
    user_verification: Literal["discouraged", "preferred", "required"] | None = Field(
        default=None,
        alias="userVerification",
    )


class WebAuthnRegistrationOptions(WebAuthnModel):
    challenge: str = Field(min_length=1)
    rp: WebAuthnRelyingPartyEntity
    user: WebAuthnUserEntity
    pub_key_cred_params: tuple[WebAuthnCredentialParameter, ...] = Field(
        default=(),
        alias="pubKeyCredParams",
    )
    timeout: int | None = Field(default=None, gt=0)
    exclude_credentials: tuple[WebAuthnCredentialDescriptor, ...] = Field(
        default=(),
        alias="excludeCredentials",
    )
    authenticator_selection: WebAuthnAuthenticatorSelection | None = Field(
        default=None,
        alias="authenticatorSelection",
    )
    attestation: Literal["direct", "enterprise", "indirect", "none"] | None = None
    hints: tuple[Literal["client-device", "hybrid", "security-key"], ...] = ()


class WebAuthnAuthenticatorAttestationResponse(WebAuthnModel):
    client_data_json: str = Field(alias="clientDataJSON", min_length=1)
    attestation_object: str = Field(alias="attestationObject", min_length=1)
    transports: (
        tuple[
            Literal["ble", "cable", "hybrid", "internal", "nfc", "smart-card", "usb"],
            ...,
        ]
        | None
    ) = None


class WebAuthnCredentialProperties(WebAuthnModel):
    rk: bool | None = None


class WebAuthnRegistrationExtensions(WebAuthnModel):
    cred_props: WebAuthnCredentialProperties | None = Field(default=None, alias="credProps")


class WebAuthnRegistrationCredential(WebAuthnModel):
    id: str = Field(min_length=1)
    raw_id: str = Field(alias="rawId", min_length=1)
    type: Literal["public-key"]
    response: WebAuthnAuthenticatorAttestationResponse
    authenticator_attachment: Literal["cross-platform", "platform"] | None = Field(
        default=None,
        alias="authenticatorAttachment",
    )
    client_extension_results: WebAuthnRegistrationExtensions = Field(
        default_factory=WebAuthnRegistrationExtensions,
        alias="clientExtensionResults",
    )


class PasskeyRegistrationBeginResponse(_StrictModel):
    challenge_id: str
    options: WebAuthnRegistrationOptions


class PasskeyRegistrationCompleteRequest(_StrictModel):
    challenge_id: str = Field(min_length=1)
    credential: WebAuthnRegistrationCredential
    name: str = Field(default="Minha Passkey", min_length=1, max_length=255)

    @field_validator("name")
    @classmethod
    def nonblank_name(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("O nome da passkey é obrigatório.")
        return normalized
