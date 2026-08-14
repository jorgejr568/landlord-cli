package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MobileAuthModelsTest {

  @Test
  fun `every known method decodes from its wire string`() {
    assertEquals(MFAMethod.TOTP, MFAMethod.fromWire("totp"))
    assertEquals(MFAMethod.RECOVERY, MFAMethod.fromWire("recovery"))
    assertEquals(MFAMethod.PASSKEY, MFAMethod.fromWire("passkey"))
  }

  @Test
  fun `an unknown method decodes to null so it can be dropped`() {
    assertNull(MFAMethod.fromWire("sms"))
    assertNull(MFAMethod.fromWire("TOTP"))
    assertNull(MFAMethod.fromWire(""))
  }

  @Test
  fun `mapping a method list keeps the known ones in order and drops the rest`() {
    val decoded = listOf("totp", "sms", "recovery", "carrier", "passkey")
      .mapNotNull(MFAMethod::fromWire)

    assertEquals(listOf(MFAMethod.TOTP, MFAMethod.RECOVERY, MFAMethod.PASSKEY), decoded)
  }

  @Test
  fun `passkey payloads compare by content, not identity`() {
    val a = PasskeyAssertionPayload(
      credentialID = byteArrayOf(1, 2),
      clientDataJSON = byteArrayOf(3),
      authenticatorData = byteArrayOf(4),
      signature = byteArrayOf(5),
      userHandle = byteArrayOf(6),
    )
    val b = PasskeyAssertionPayload(
      credentialID = byteArrayOf(1, 2),
      clientDataJSON = byteArrayOf(3),
      authenticatorData = byteArrayOf(4),
      signature = byteArrayOf(5),
      userHandle = byteArrayOf(6),
    )
    val differsInUserHandle = PasskeyAssertionPayload(
      credentialID = byteArrayOf(1, 2),
      clientDataJSON = byteArrayOf(3),
      authenticatorData = byteArrayOf(4),
      signature = byteArrayOf(5),
      userHandle = null,
    )

    assertEquals(a, b)
    assertEquals(a.hashCode(), b.hashCode())
    assert(a != differsInUserHandle)
  }
}
