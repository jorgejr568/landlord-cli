import Foundation

/// Unpadded base64url ("base64url encoding without padding", RFC 4648 §5) — the encoding every
/// WebAuthn field on the Rentivo contract uses.
///
/// This deliberately mirrors the web client byte for byte
/// (`frontend/src/features/auth/webauthn.ts`): encoding maps `+`→`-`, `/`→`_` and strips the `=`
/// padding, and decoding reverses that, re-adding the padding `Data(base64Encoded:)` insists on.
/// The server accepts unpadded input (py_webauthn's `base64url_to_bytes` pads for itself), so the
/// two clients put identical bytes on the wire.
enum Base64URL {
  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ value: String) -> Data? {
    var base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
    return Data(base64Encoded: base64)
  }
}
