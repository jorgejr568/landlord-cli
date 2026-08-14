package app.rentivo.data.api

import java.util.Base64

/**
 * Unpadded base64url ("base64url encoding without padding", RFC 4648 §5) — the encoding every
 * WebAuthn field on the Rentivo contract uses. Port of `ios/Rentivo/Data/API/Base64URL.swift`.
 *
 * This deliberately mirrors the web and iOS clients byte for byte
 * (`frontend/src/features/auth/webauthn.ts`): encoding maps `+`→`-`, `/`→`_` and strips the `=`
 * padding, and decoding reverses that. `java.util.Base64`'s URL decoder tolerates the missing
 * padding, so the server (py_webauthn's `base64url_to_bytes`, which pads for itself) accepts the
 * identical bytes every client puts on the wire.
 */
internal object Base64URL {
  private val encoder = Base64.getUrlEncoder().withoutPadding()
  private val decoder = Base64.getUrlDecoder()

  fun encode(bytes: ByteArray): String = encoder.encodeToString(bytes)

  /** The bytes behind [value], or `null` when it is not valid base64url. */
  fun decode(value: String): ByteArray? =
    runCatching { decoder.decode(value) }.getOrNull()
}
