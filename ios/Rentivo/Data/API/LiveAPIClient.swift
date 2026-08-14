import Foundation

struct LiveSession: Sendable, Equatable {
  let accessToken: String
  let profile: UserProfile
}

/// `LiveSession`-flavoured `MobileLoginOutcome`. The public Domain enum carries a `UserProfile`
/// because `LiveSession` is internal on purpose — the access token stays inside this module — so
/// the two shapes exist side by side and `APIRentivoStore` maps one onto the other.
enum LiveLoginOutcome: Sendable, Equatable {
  case authenticated(LiveSession)
  case mfaRequired(MFAChallenge)
}

public enum LiveAPIError: LocalizedError, Sendable, Equatable {
  case server(message: String, statusCode: Int? = nil)
  case invalidResponse
  case sessionExpired

  public var errorDescription: String? {
    switch self {
    case .server(let message, _): message
    case .invalidResponse: "Não foi possível interpretar a resposta do Rentivo."
    case .sessionExpired: "Sua sessão expirou. Entre novamente para continuar."
    }
  }

  public var statusCode: Int? {
    guard case let .server(_, statusCode) = self else { return nil }
    return statusCode
  }
}

extension Notification.Name {
  /// Posted whenever `LiveAPIClient` observes a 401 response (or discovers it
  /// has no stored token) while serving an authenticated request. `AppModel`
  /// observes this to move the app back to the anonymous state; posting is
  /// harmless if nothing is listening (e.g. before the app has authenticated).
  public static let liveAPIClientSessionExpired = Notification.Name("LiveAPIClient.sessionExpired")
}

// `public` only so app targets can read `productionURL` (the "Sobre e suporte" links point at the
// same site the client talks to). Every member below stays internal, including `init`, so this
// widens the module's API surface by exactly the type name and that one address.
public actor LiveAPIClient {
  public static let productionURL = URL(string: "https://rentivo.com.br")!

  private let session: URLSession
  private let credentials: any CredentialStore
  private let downloads: DownloadedFileStore
  private var accessToken: String?

  init(
    session: URLSession? = nil, credentials: any CredentialStore,
    downloads: DownloadedFileStore = .shared
  ) {
    self.session = session ?? Self.makeSession()
    self.credentials = credentials
    self.downloads = downloads
  }

  /// The app's default session. Unlike `URLSession.shared` it bounds each request
  /// so a stalled connection (e.g. the iOS Simulator's flaky HTTP/3 path, or a
  /// dropped mobile network) fails fast and stays retryable instead of freezing
  /// the UI on the system default timeout. Tests inject their own stubbed session.
  ///
  /// It also opts out of `URLCache` completely. `URLSessionConfiguration.default` binds to the
  /// disk-backed `URLCache.shared`, so authenticated payloads — PIX details on a billing, tenant
  /// names and e-mail addresses on a contact, and downloaded documents — would be written into the
  /// app container purely as a side effect of the transport. Worse, because these routes send no
  /// `Cache-Control`, `URLCache` applied heuristic freshness and *did* serve them: a poll for
  /// `pdf_render_status` re-read its own cached "pending" response instead of the network and
  /// never observed the render finishing. The app is a thin client over a live API with no
  /// offline mode, so nothing is lost by dropping the cache. `URLSessionConfiguration.ephemeral`
  /// is not used instead because it still installs a (memory-backed) `URLCache` and would
  /// additionally move cookie and credential storage — an unrelated behavior change.
  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }

  /// Translates a `URLSession` transport failure (thrown before any HTTP response
  /// arrives) into a `LiveAPIError` carrying an actionable PT-BR message. Without
  /// this, a `URLError` propagates raw and the login screen and app-wide error
  /// mapping fall through to a generic message with no connectivity/retry cue.
  private func transportError(from error: Error) -> Error {
    guard let urlError = error as? URLError else { return error }
    switch urlError.code {
    case .timedOut:
      return LiveAPIError.server(
        message: "O Rentivo demorou para responder. Verifique sua conexão e tente novamente.")
    case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
      .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
      return LiveAPIError.server(
        message: "Sem conexão com o Rentivo. Verifique sua internet e tente novamente.")
    default:
      return LiveAPIError.server(
        message: "Não foi possível conectar ao Rentivo. Tente novamente.")
    }
  }

  func exchangeMobileAuthorization(code: String) async throws -> LiveSession {
    let response: LoginResponse = try await send(
      path: "/api/v1/auth/mobile/exchange", method: "POST",
      body: MobileAuthorizationExchangeRequest(authorizationCode: code), token: nil
    )
    return try await adopt(response)
  }

  // MARK: - Native (Turnstile-free) authentication
  //
  // `/api/v1/auth/mobile/{login,signup}` and the MFA follow-ups all speak `credential_transport
  // = "body"`: no cookies, no CSRF token, the credential comes back as a bearer token. The server
  // deliberately stalls ~4 s before *every* failure (the tarpit that replaces Turnstile), so these
  // calls have to sit well inside `makeSession()`'s 30 s request timeout — and must never be
  // retried automatically, since a retry both burns one of the 4-per-minute attempts and doubles
  // the wait the user sees.

  func mobileLogin(email: String, password: String) async throws -> LiveLoginOutcome {
    let (data, statusCode) = try await sendRaw(
      path: "/api/v1/auth/mobile/login", method: "POST",
      body: MobileCredentialsRequest(email: email, password: password), token: nil
    )
    guard statusCode != 202 else {
      return .mfaRequired(try challenge(from: decode(MFARequiredResponse.self, from: data)))
    }
    return .authenticated(try await adopt(decode(LoginResponse.self, from: data)))
  }

  func mobileSignup(email: String, password: String) async throws -> LiveSession {
    let response: LoginResponse = try await send(
      path: "/api/v1/auth/mobile/signup", method: "POST",
      body: MobileCredentialsRequest(email: email, password: password), token: nil
    )
    return try await adopt(response)
  }

  func verifyTotp(challenge: MFAChallenge, code: String) async throws -> LiveSession {
    try await verifyCode(path: "/api/v1/auth/mfa/totp/verify", challenge: challenge, code: code)
  }

  func verifyRecoveryCode(challenge: MFAChallenge, code: String) async throws -> LiveSession {
    try await verifyCode(path: "/api/v1/auth/mfa/recovery/verify", challenge: challenge, code: code)
  }

  func beginPasskeyAssertion(challenge: MFAChallenge) async throws -> PasskeyRequestOptions {
    let response: WebAuthnOptionsResponse = try await send(
      path: "/api/v1/auth/mfa/passkeys/begin", method: "POST",
      body: MFAChallengeRequest(challenge: challenge), token: nil
    )
    guard let decodedChallenge = Base64URL.decode(response.challenge) else {
      throw LiveAPIError.invalidResponse
    }
    var allowedCredentialIDs: [Data] = []
    for descriptor in response.allowCredentials {
      guard let credentialID = Base64URL.decode(descriptor.id) else {
        throw LiveAPIError.invalidResponse
      }
      allowedCredentialIDs.append(credentialID)
    }
    return PasskeyRequestOptions(
      challenge: decodedChallenge,
      relyingPartyIdentifier: response.rpId,
      allowedCredentialIDs: allowedCredentialIDs,
      userVerification: response.userVerification,
      timeoutMilliseconds: response.timeout
    )
  }

  func completePasskeyAssertion(
    challenge: MFAChallenge, credential: PasskeyAssertionPayload
  ) async throws -> LiveSession {
    let response: LoginResponse = try await send(
      path: "/api/v1/auth/mfa/passkeys/complete", method: "POST",
      body: PasskeyCompleteRequest(challenge: challenge, credential: credential), token: nil
    )
    return try await adopt(response)
  }

  private func verifyCode(path: String, challenge: MFAChallenge, code: String) async throws -> LiveSession {
    let response: LoginResponse = try await send(
      path: path, method: "POST",
      body: MFACodeVerifyRequest(challenge: challenge, code: code), token: nil
    )
    return try await adopt(response)
  }

  private func challenge(from response: MFARequiredResponse) throws -> MFAChallenge {
    guard response.credentialTransport == "body", let challengeToken = response.challengeToken else {
      throw LiveAPIError.invalidResponse
    }
    return MFAChallenge(
      challengeId: response.challengeId,
      challengeToken: challengeToken,
      // Unknown method strings are dropped rather than surfaced; see `MFAMethod`.
      methods: response.methods.compactMap(MFAMethod.init(rawValue:))
    )
  }

  /// Takes ownership of a freshly minted body-transport session: validates the envelope, keeps the
  /// bearer token in memory, and persists it. Shared by every native sign-in entry point and by
  /// `exchangeMobileAuthorization`.
  private func adopt(_ response: LoginResponse) async throws -> LiveSession {
    guard response.credentialTransport == "body", let accessToken = response.accessToken,
      let user = response.bootstrap?.user
    else { throw LiveAPIError.invalidResponse }
    self.accessToken = accessToken
    try await credentials.saveAccessToken(accessToken)
    return LiveSession(accessToken: accessToken, profile: UserProfile(id: user.id, email: user.email))
  }

  func restoreSession() async throws -> LiveSession? {
    guard let storedToken = try await credentials.readAccessToken() else { return nil }
    do {
      let response: SessionResponse = try await send(
        path: "/api/v1/auth/session", method: "GET", body: Optional<String>.none, token: storedToken
      )
      accessToken = storedToken
      return LiveSession(
        accessToken: storedToken,
        profile: UserProfile(id: response.bootstrap.user.id, email: response.bootstrap.user.email)
      )
    } catch let error as LiveAPIError where error.statusCode == 401 {
      await invalidateSession()
      return nil
    }
  }

  func request(
    path: String, method: String = "GET", body: Data? = nil,
    contentType: String = "application/json"
  ) async throws -> Data {
    guard let accessToken else {
      throw LiveAPIError.sessionExpired
    }
    var request = URLRequest(url: Self.productionURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw transportError(from: error)
    }
    guard let http = response as? HTTPURLResponse else { throw LiveAPIError.invalidResponse }
    if http.statusCode == 401 {
      await invalidateSession()
      throw LiveAPIError.sessionExpired
    }
    guard (200..<300).contains(http.statusCode) else {
      let problem = try? JSONDecoder().decode(ProblemResponse.self, from: data)
      throw LiveAPIError.server(
        message: problem?.detail ?? "Não foi possível concluir a solicitação.", statusCode: http.statusCode
      )
    }
    return data
  }

  func logout() async {
    accessToken = nil
    try? await credentials.deleteAccessToken()
    purgeLocalArtifacts()
  }

  /// Clears the in-memory token and the persisted credential, then notifies
  /// any observers (see `AppModel`) that the session is no longer valid.
  private func invalidateSession() async {
    accessToken = nil
    try? await credentials.deleteAccessToken()
    purgeLocalArtifacts()
    NotificationCenter.default.post(name: .liveAPIClientSessionExpired, object: nil)
  }

  /// Drops what an authenticated session leaves behind on disk: documents the user downloaded
  /// through the share sheet, and any response an earlier build stored in `URLCache.shared`.
  /// `makeSession()` no longer uses that cache, but a build shipped before it stopped may have
  /// written to it and nothing else would ever clear it.
  private func purgeLocalArtifacts() {
    URLCache.shared.removeAllCachedResponses()
    downloads.purge()
  }

  func download(path: String, filename: String, mediaType: String = "application/pdf") async throws -> DownloadedFile {
    guard let accessToken else {
      throw LiveAPIError.sessionExpired
    }
    var request = URLRequest(url: Self.productionURL.appending(path: path))
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(mediaType, forHTTPHeaderField: "Accept")
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw transportError(from: error)
    }
    guard let http = response as? HTTPURLResponse else { throw LiveAPIError.invalidResponse }
    if http.statusCode == 401 {
      await invalidateSession()
      throw LiveAPIError.sessionExpired
    }
    guard (200..<300).contains(http.statusCode) else {
      throw LiveAPIError.server(message: "Não foi possível baixar o arquivo.")
    }
    let responseMediaType = (http.value(forHTTPHeaderField: "Content-Type") ?? mediaType)
      .split(separator: ";", maxSplits: 1).first.map(String.init) ?? mediaType
    let resolvedFilename = filename.contains(".")
      ? filename
      : "\(filename).\(fileExtension(for: responseMediaType))"
    let destination = try downloads.makeDestination(
      pathExtension: (resolvedFilename as NSString).pathExtension)
    try data.write(to: destination, options: DownloadedFileStore.writingOptions)
    return DownloadedFile(fileURL: destination, filename: resolvedFilename, mediaType: responseMediaType)
  }

  private func fileExtension(for mediaType: String) -> String {
    switch mediaType.lowercased() {
    case "application/pdf": "pdf"
    case "image/jpeg": "jpg"
    case "image/png": "png"
    case "image/heic": "heic"
    case "text/plain": "txt"
    default: "bin"
    }
  }

  private func send<Body: Encodable, Response: Decodable>(
    path: String,
    method: String,
    body: Body?,
    token: String?
  ) async throws -> Response {
    let (data, _) = try await sendRaw(path: path, method: method, body: body, token: token)
    return try decode(Response.self, from: data)
  }

  /// The transport half of `send`: performs the request, maps transport failures and non-2xx
  /// problem documents onto `LiveAPIError`, and hands back the raw body *plus the status code*.
  /// `mobileLogin` needs the code because `200` (session) and `202` (MFA challenge) are both
  /// successes carrying different schemas.
  private func sendRaw<Body: Encodable>(
    path: String,
    method: String,
    body: Body?,
    token: String?
  ) async throws -> (Data, Int) {
    var request = URLRequest(url: Self.productionURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw transportError(from: error)
    }
    guard let http = response as? HTTPURLResponse else { throw LiveAPIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let problem = try? JSONDecoder().decode(ProblemResponse.self, from: data)
      throw LiveAPIError.server(
        message: problem?.detail ?? "Não foi possível concluir a solicitação.", statusCode: http.statusCode
      )
    }
    return (data, http.statusCode)
  }

  private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw LiveAPIError.invalidResponse
    }
  }
}

private struct LoginResponse: Decodable {
  let credentialTransport: String
  let accessToken: String?
  let bootstrap: BootstrapResponse?

  enum CodingKeys: String, CodingKey {
    case credentialTransport = "credential_transport"
    case accessToken = "access_token"
    case bootstrap
  }
}

private struct SessionResponse: Decodable {
  let bootstrap: BootstrapResponse
}

private struct BootstrapResponse: Decodable {
  let user: BootstrapUser
}

private struct BootstrapUser: Decodable {
  let id: Int
  let email: String
}

/// `BodyMFARequiredResponse`. `challenge_id` identifies the challenge row; `challenge_token` is
/// the nonce that authenticates the caller against it in the absence of the challenge cookie.
private struct MFARequiredResponse: Decodable {
  let credentialTransport: String
  let challengeId: String
  let challengeToken: String?
  let methods: [String]

  enum CodingKeys: String, CodingKey {
    case credentialTransport = "credential_transport"
    case challengeId = "challenge_id"
    case challengeToken = "challenge_token"
    case methods
  }
}

private struct MobileCredentialsRequest: Encodable {
  let email: String
  let password: String
}

/// `BodyPasskeyAuthBeginRequest` — the smallest body-transport challenge envelope, also the
/// prefix every other MFA request repeats.
private struct MFAChallengeRequest: Encodable {
  let credentialTransport = "body"
  let challengeId: String
  let challengeToken: String

  init(challenge: MFAChallenge) {
    challengeId = challenge.challengeId
    challengeToken = challenge.challengeToken
  }

  enum CodingKeys: String, CodingKey {
    case credentialTransport = "credential_transport"
    case challengeId = "challenge_id"
    case challengeToken = "challenge_token"
  }
}

/// `BodyMFACodeVerifyRequest`, shared by the TOTP and recovery-code routes.
private struct MFACodeVerifyRequest: Encodable {
  let credentialTransport = "body"
  let challengeId: String
  let challengeToken: String
  let code: String

  init(challenge: MFAChallenge, code: String) {
    challengeId = challenge.challengeId
    challengeToken = challenge.challengeToken
    self.code = code
  }

  enum CodingKeys: String, CodingKey {
    case credentialTransport = "credential_transport"
    case challengeId = "challenge_id"
    case challengeToken = "challenge_token"
    case code
  }
}

/// `BodyPasskeyAuthCompleteRequest`. The nested credential is `WebAuthnAuthenticationCredential`
/// and keeps the contract's camelCase field names verbatim — unlike the snake_case envelope
/// around it, those come straight from the WebAuthn spec.
private struct PasskeyCompleteRequest: Encodable {
  let credentialTransport = "body"
  let challengeId: String
  let challengeToken: String
  let credential: WireAssertionCredential

  init(challenge: MFAChallenge, credential: PasskeyAssertionPayload) {
    challengeId = challenge.challengeId
    challengeToken = challenge.challengeToken
    self.credential = WireAssertionCredential(credential)
  }

  enum CodingKeys: String, CodingKey {
    case credentialTransport = "credential_transport"
    case challengeId = "challenge_id"
    case challengeToken = "challenge_token"
    case credential
  }
}

private struct WireAssertionCredential: Encodable {
  let id: String
  let rawId: String
  let type = "public-key"
  let response: WireAssertionResponse

  init(_ payload: PasskeyAssertionPayload) {
    // The web client sends `id` (the WebAuthn credential's `id` string, already base64url) and
    // `rawId` (base64url of the same bytes) — identical values. `AuthenticationServices` only
    // hands back the raw `credentialID`, so both are derived from it here.
    id = Base64URL.encode(payload.credentialID)
    rawId = id
    response = WireAssertionResponse(payload)
  }
}

private struct WireAssertionResponse: Encodable {
  let clientDataJSON: String
  let authenticatorData: String
  let signature: String
  let userHandle: String?

  init(_ payload: PasskeyAssertionPayload) {
    clientDataJSON = Base64URL.encode(payload.clientDataJSON)
    authenticatorData = Base64URL.encode(payload.authenticatorData)
    signature = Base64URL.encode(payload.signature)
    // Omitted entirely when absent, matching the web client's conditional spread.
    userHandle = payload.userHandle.map(Base64URL.encode)
  }
}

/// `WebAuthnAuthenticationOptions`.
private struct WebAuthnOptionsResponse: Decodable {
  let challenge: String
  let timeout: Int
  let rpId: String
  let allowCredentials: [Descriptor]
  let userVerification: String

  struct Descriptor: Decodable {
    let id: String
  }
}

private struct MobileAuthorizationExchangeRequest: Encodable {
  let authorizationCode: String
  enum CodingKeys: String, CodingKey { case authorizationCode = "authorization_code" }
}

private struct ProfileResponse: Decodable {
  let email: String
}

private struct ProblemResponse: Decodable {
  let detail: String?
}
