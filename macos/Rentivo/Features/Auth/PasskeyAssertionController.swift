import AppKit
import AuthenticationServices
import Foundation
import RentivoCore

/// Runs one WebAuthn assertion ("chave de acesso") for a login challenge and hands the raw
/// authenticator output back as the Domain payload the Data layer re-encodes for the server.
///
/// A macOS port of the iOS controller of the same name: `AuthenticationServices` speaks the same
/// delegate protocol on both platforms, so the only real difference is the presentation anchor —
/// an `NSWindow` here rather than a `UIWindow`. One controller per `assert(options:)`: the system
/// UI is modal, and the login screen never has two challenges in flight.
@MainActor
final class PasskeyAssertionController: NSObject {
  /// Why an assertion produced no payload. `cancelled` is the user closing the system sheet —
  /// an expected outcome the login screen swallows rather than reporting as an error.
  enum Failure: Error, Equatable {
    case cancelled
    case unsupportedCredential
  }

  private var continuation: CheckedContinuation<PasskeyAssertionPayload, Error>?
  /// Held only to keep the controller alive while the system sheet is up;
  /// `ASAuthorizationController` is not retained by the system and a released one never calls back.
  private var controller: ASAuthorizationController?

  func assert(options: PasskeyRequestOptions) async throws -> PasskeyAssertionPayload {
    // The server's `userVerification` travels as the WebAuthn wire string ("required",
    // "preferred", "discouraged"), which is exactly this option set's raw value.
    let userVerification = ASAuthorizationPublicKeyCredentialUserVerificationPreference(
      rawValue: options.userVerification)

    let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: options.relyingPartyIdentifier)
    let platformRequest = platformProvider.createCredentialAssertionRequest(
      challenge: options.challenge)
    platformRequest.allowedCredentials = options.allowedCredentialIDs.map {
      ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
    }
    platformRequest.userVerificationPreference = userVerification

    // The same challenge again for detached authenticators. The server lists a user's credentials
    // without saying which kind each one is, so a user whose only registered key is a USB/NFC
    // security key (or any non-Apple provider) would otherwise be shown a sheet with nothing to
    // offer. Both requests go into one `performRequests` call so the system presents a single sheet
    // covering whichever authenticator is actually present.
    let securityKeyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(
      relyingPartyIdentifier: options.relyingPartyIdentifier)
    let securityKeyRequest = securityKeyProvider.createCredentialAssertionRequest(
      challenge: options.challenge)
    securityKeyRequest.allowedCredentials = options.allowedCredentialIDs.map {
      // The begin response's per-credential `transports` are not carried into
      // `PasskeyRequestOptions`, so every transport this platform supports is allowed rather than
      // guessing one and locking out a key that speaks another.
      ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
        credentialID: $0,
        transports: ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported)
    }
    securityKeyRequest.userVerificationPreference = userVerification

    defer { controller = nil }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let controller = ASAuthorizationController(
        authorizationRequests: [platformRequest, securityKeyRequest])
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
    // Matched on the shared protocol, not on the platform concrete type: a security-key assertion
    // carries the same five WebAuthn fields and encodes identically for the server.
    guard
      let assertion = authorization.credential as? ASAuthorizationPublicKeyCredentialAssertion
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
    // The window the system sheet attaches to, in the same key -> main -> first order the
    // browser hand-off used, or a placeholder when the app has no window yet.
    NSApplication.shared.keyWindow
      ?? NSApplication.shared.mainWindow
      ?? NSApplication.shared.windows.first
      ?? ASPresentationAnchor()
  }
}
