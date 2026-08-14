import Foundation

/// A second factor the server is willing to accept for a pending login challenge.
///
/// The contract types `methods` as a bare `array[string]` (see `BodyMFARequiredResponse` in
/// `openapi.json`), so the values are not pinned by the schema; `login_service._mfa_methods`
/// emits `totp`, `recovery`, and `passkey`. Decoding therefore **drops** values this build does
/// not know instead of failing or smuggling them through as an opaque case: a method the app
/// cannot present is not actionable, and an unknown string must never crash the login screen.
/// A challenge whose methods are all unknown decodes to an empty `methods` array, which the UI
/// has to treat as "no factor available here" rather than as a decoding error.
public enum MFAMethod: String, Sendable, Hashable, CaseIterable {
  case totp
  case recovery
  case passkey
}

/// A login that stopped at the MFA step.
///
/// Both identifiers are load-bearing: `mfa_auth` looks the challenge up by `challenge_id` and
/// authenticates the caller against it with `challenge_token` (the body-transport stand-in for
/// the browser's challenge cookie), so every follow-up call has to carry the pair.
public struct MFAChallenge: Sendable, Equatable {
  public let challengeId: String
  public let challengeToken: String
  public let methods: [MFAMethod]

  public init(challengeId: String, challengeToken: String, methods: [MFAMethod]) {
    self.challengeId = challengeId
    self.challengeToken = challengeToken
    self.methods = methods
  }
}

/// The two shapes `POST /api/v1/auth/mobile/login` can settle on: `200` with a session, or `202`
/// with a challenge to finish.
public enum MobileLoginOutcome: Sendable, Equatable {
  case authenticated(UserProfile)
  case mfaRequired(MFAChallenge)
}

/// `WebAuthnAuthenticationOptions` decoded into the form `AuthenticationServices` wants.
///
/// The wire format carries `challenge` and every `allowCredentials[].id` as base64url text;
/// `ASAuthorizationPlatformPublicKeyCredentialProvider` wants raw bytes, so the decoding happens
/// here once and the rest of the app only ever sees `Data`.
public struct PasskeyRequestOptions: Sendable, Equatable {
  public let challenge: Data
  public let relyingPartyIdentifier: String
  public let allowedCredentialIDs: [Data]
  public let userVerification: String
  public let timeoutMilliseconds: Int

  public init(
    challenge: Data,
    relyingPartyIdentifier: String,
    allowedCredentialIDs: [Data],
    userVerification: String,
    timeoutMilliseconds: Int
  ) {
    self.challenge = challenge
    self.relyingPartyIdentifier = relyingPartyIdentifier
    self.allowedCredentialIDs = allowedCredentialIDs
    self.userVerification = userVerification
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}

/// The assertion an authenticator produced, in raw bytes.
///
/// Mirrors the fields `ASAuthorizationPlatformPublicKeyCredentialAssertion` exposes. The Data
/// layer re-encodes them as base64url into `WebAuthnAuthenticationCredential`, matching exactly
/// what the web client sends (`frontend/src/features/auth/webauthn.ts`): `id` and `rawId` are both
/// the base64url credential ID, and `type` is always `public-key`.
public struct PasskeyAssertionPayload: Sendable, Equatable {
  public let credentialID: Data
  public let clientDataJSON: Data
  public let authenticatorData: Data
  public let signature: Data
  public let userHandle: Data?

  public init(
    credentialID: Data,
    clientDataJSON: Data,
    authenticatorData: Data,
    signature: Data,
    userHandle: Data? = nil
  ) {
    self.credentialID = credentialID
    self.clientDataJSON = clientDataJSON
    self.authenticatorData = authenticatorData
    self.signature = signature
    self.userHandle = userHandle
  }
}
