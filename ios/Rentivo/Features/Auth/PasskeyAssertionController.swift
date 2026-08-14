import AuthenticationServices
import Foundation

/// Runs one WebAuthn assertion ("chave de acesso") for a login challenge and hands the raw
/// authenticator output back as the Domain payload the Data layer re-encodes for the server.
///
/// `AuthenticationServices` only speaks delegate callbacks, so this wraps a single
/// `ASAuthorizationController` in an `async` call. One controller per `assert(options:)`: the
/// system UI is modal, and the login screen never has two challenges in flight.
@MainActor
final class PasskeyAssertionController: NSObject {
  /// Why an assertion produced no payload. `cancelled` is the user closing the system sheet —
  /// an expected outcome the login screen swallows rather than reporting as an error, exactly
  /// like `MobileWebAuthenticator.isUserCancellation` on the browser path.
  enum Failure: Error, Equatable {
    case cancelled
    case unsupportedCredential
  }

  private var continuation: CheckedContinuation<PasskeyAssertionPayload, Error>?
  /// Held only to keep the controller alive while the system sheet is up; `ASAuthorizationController`
  /// is not retained by the system and a released one never calls back.
  private var controller: ASAuthorizationController?

  func assert(options: PasskeyRequestOptions) async throws -> PasskeyAssertionPayload {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: options.relyingPartyIdentifier)
    let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
    request.allowedCredentials = options.allowedCredentialIDs.map {
      ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
    }
    // The server's `userVerification` travels as the WebAuthn wire string ("required",
    // "preferred", "discouraged"), which is exactly this option set's raw value.
    request.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference(
      rawValue: options.userVerification)
    defer { controller = nil }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      self.controller = controller
      controller.performRequests()
    }
  }

  /// Whether `error` is the user dismissing the system passkey sheet, as opposed to a genuine
  /// failure worth putting on screen.
  static func isUserCancellation(_ error: Error) -> Bool {
    if case Failure.cancelled = error { return true }
    return (error as? ASAuthorizationError)?.code == .canceled
  }

  /// Resumes the pending `assert(options:)` exactly once; later callbacks (the system can report
  /// a completion and a cancellation for the same request) are dropped.
  private func finish(with result: Result<PasskeyAssertionPayload, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}

extension PasskeyAssertionController: ASAuthorizationControllerDelegate {
  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard
      let assertion = authorization.credential
        as? ASAuthorizationPlatformPublicKeyCredentialAssertion
    else {
      finish(with: .failure(Failure.unsupportedCredential))
      return
    }
    finish(
      with: .success(
        PasskeyAssertionPayload(
          credentialID: assertion.credentialID,
          clientDataJSON: assertion.rawClientDataJSON,
          authenticatorData: assertion.rawAuthenticatorData,
          signature: assertion.signature,
          // The contract's `userHandle` is optional and the authenticator may return nothing;
          // an empty blob is "absent", not a zero-length handle.
          userHandle: assertion.userID.isEmpty ? nil : assertion.userID
        )))
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    guard (error as? ASAuthorizationError)?.code != .canceled else {
      finish(with: .failure(Failure.cancelled))
      return
    }
    finish(with: .failure(error))
  }
}

extension PasskeyAssertionController: ASAuthorizationControllerPresentationContextProviding {
  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    // Same key-window resolution the browser hand-off uses; see `MobileWebAuthenticator`.
    MobileWebAuthenticator.currentPresentationAnchor()
  }
}
