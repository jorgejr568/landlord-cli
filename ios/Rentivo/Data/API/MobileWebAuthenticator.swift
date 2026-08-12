import Foundation

enum MobileWebAuthenticationFlow {
  static func authorizationURL(baseURL: URL, state: String) -> URL {
    url(baseURL: baseURL, path: "/login", queryItem: URLQueryItem(name: "mobile_state", value: state))
  }

  static func logoutURL(baseURL: URL, state: String) -> URL {
    url(baseURL: baseURL, path: "/mobile-logout", queryItem: URLQueryItem(name: "state", value: state))
  }

  static func authorizationCode(from callbackURL: URL, expectedState: String) -> String? {
    guard let callback = callback(callbackURL, path: "/callback", expectedState: expectedState),
      let code = callback.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else { return nil }
    return code
  }

  static func isLogoutCallback(_ callbackURL: URL, expectedState: String) -> Bool {
    callback(callbackURL, path: "/logout", expectedState: expectedState) != nil
  }

  private static func url(baseURL: URL, path: String, queryItem: URLQueryItem) -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
    components.queryItems = [queryItem]
    return components.url!
  }

  private static func callback(
    _ callbackURL: URL, path: String, expectedState: String
  ) -> URLComponents? {
    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      components.scheme == "rentivo",
      components.host == "auth",
      components.path == path,
      components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState
    else { return nil }
    return components
  }
}

// AuthenticationServices drives the browser session on both Apple platforms;
// only the presentation anchor differs, so the flow lives in one place and the
// anchor is resolved by a per-platform extension below. Non-Apple platforms
// (where neither UIKit nor AppKit exists) get the stub at the end of the file.
#if canImport(UIKit) || canImport(AppKit)
import AuthenticationServices

@MainActor
public final class MobileWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?

  public override init() {
    super.init()
  }

  public func authorize() async throws -> String {
    let state = UUID().uuidString
    let url = MobileWebAuthenticationFlow.authorizationURL(
      baseURL: LiveAPIClient.productionURL, state: state)
    // The session is released here, back on the main actor, rather than from
    // the completion handler — see `authorizationResult(callbackURL:error:expectedState:)`.
    defer { session = nil }
    return try await withCheckedThrowingContinuation { continuation in
      let webSession = ASWebAuthenticationSession(
        url: url, callbackURLScheme: "rentivo"
      ) { @Sendable callbackURL, error in
        continuation.resume(
          with: Self.authorizationResult(
            callbackURL: callbackURL, error: error, expectedState: state))
      }
      configure(webSession)
      guard webSession.start() else {
        continuation.resume(throwing: LiveAPIError.invalidResponse)
        return
      }
    }
  }

  public func logout() async throws {
    let state = UUID().uuidString
    let url = MobileWebAuthenticationFlow.logoutURL(
      baseURL: LiveAPIClient.productionURL, state: state)
    defer { session = nil }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let webSession = ASWebAuthenticationSession(
        url: url, callbackURLScheme: "rentivo"
      ) { @Sendable callbackURL, error in
        continuation.resume(
          with: Self.logoutResult(
            callbackURL: callbackURL, error: error, expectedState: state))
      }
      configure(webSession)
      guard webSession.start() else {
        continuation.resume(throwing: LiveAPIError.invalidResponse)
        return
      }
    }
  }

  /// Turns an `ASWebAuthenticationSession` login completion into the value the
  /// suspended `authorize()` call resumes with.
  ///
  /// Deliberately `nonisolated` and only ever called from a `@Sendable`
  /// completion handler: on macOS AuthenticationServices replies on an
  /// arbitrary XPC queue (`com.apple.NSXPCConnection…SafariLaunchAgent`), so a
  /// main-actor-isolated completion body traps in Swift 6's executor check.
  /// Nothing on this path may touch main-actor state; resuming a continuation
  /// is thread-safe, and the session cleanup happens in the caller after the
  /// `await`.
  nonisolated static func authorizationResult(
    callbackURL: URL?, error: Error?, expectedState: String
  ) -> Result<String, Error> {
    if let error { return .failure(error) }
    guard let callbackURL,
      let code = MobileWebAuthenticationFlow.authorizationCode(
        from: callbackURL, expectedState: expectedState)
    else { return .failure(LiveAPIError.invalidResponse) }
    return .success(code)
  }

  /// The `logout()` counterpart of `authorizationResult`, and `nonisolated` for
  /// exactly the same reason.
  nonisolated static func logoutResult(
    callbackURL: URL?, error: Error?, expectedState: String
  ) -> Result<Void, Error> {
    if let error { return .failure(error) }
    guard let callbackURL,
      MobileWebAuthenticationFlow.isLogoutCallback(callbackURL, expectedState: expectedState)
    else { return .failure(LiveAPIError.invalidResponse) }
    return .success(())
  }

  /// Whether `error` represents the user dismissing the authentication sheet
  /// themselves, as opposed to a genuine failure. Shared by `AppModel`
  /// (best-effort browser logout) and the login screen (silence expected
  /// cancellations instead of surfacing an English system message).
  /// `nonisolated` so it can also classify an error produced on the
  /// AuthenticationServices reply queue.
  public nonisolated static func isUserCancellation(_ error: Error) -> Bool {
    (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
  }

  private func configure(_ webSession: ASWebAuthenticationSession) {
    webSession.presentationContextProvider = self
    // Login and logout must use the same shared browser cookie jar as the website.
    webSession.prefersEphemeralWebBrowserSession = false
    session = webSession
  }

  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    Self.currentPresentationAnchor()
  }
}

#if canImport(UIKit)
import UIKit

extension MobileWebAuthenticator {
  /// The key window of the foreground scene, or a placeholder when the app has
  /// no window yet.
  static func currentPresentationAnchor() -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? UIWindow()
  }
}
#elseif canImport(AppKit)
import AppKit

extension MobileWebAuthenticator {
  /// The window the authentication sheet is attached to, or a placeholder when
  /// the app has no window yet (for example a menu-bar-only launch).
  static func currentPresentationAnchor() -> ASPresentationAnchor {
    preferredAnchor(
      key: NSApplication.shared.keyWindow,
      main: NSApplication.shared.mainWindow,
      first: NSApplication.shared.windows.first
    ) ?? ASPresentationAnchor()
  }

  /// The anchor preference order, kept free of `NSApplication` so it stays
  /// testable without a running application.
  nonisolated static func preferredAnchor<Window: AnyObject>(
    key: Window?, main: Window?, first: Window?
  ) -> Window? {
    key ?? main ?? first
  }
}
#endif
#else
@MainActor
public final class MobileWebAuthenticator {
  public init() {}

  public func authorize() async throws -> String {
    throw LiveAPIError.server(
      message: "A autenticação pelo navegador requer o aplicativo nativo do Rentivo."
    )
  }

  public func logout() async throws {
    throw LiveAPIError.server(
      message: "A saída pelo navegador requer o aplicativo nativo do Rentivo."
    )
  }
}
#endif
