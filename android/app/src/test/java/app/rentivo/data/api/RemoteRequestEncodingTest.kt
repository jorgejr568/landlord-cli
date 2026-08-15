package app.rentivo.data.api

import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ThemeValues
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Request DTOs whose only contract is their field names, mirroring the iOS
 * `PasswordChangeRequestTests` / `CommunicationPreviewRequestTests` unit suites.
 */
class RemoteRequestEncodingTest {

  private fun fields(json: String): Map<String, String?> = apiJson.parseToJsonElement(json)
    .jsonObject
    .mapValues { (_, value) -> value.jsonPrimitive.contentOrNull }

  @Test
  fun `the password change request uses the api contract field names`() {
    val encoded = apiJson.encodeToString(
      RemotePasswordChange(
        currentPassword = "old-password",
        newPassword = "new-password",
        confirmPassword = "new-password",
      )
    )

    assertEquals(
      mapOf(
        "current_password" to "old-password",
        "new_password" to "new-password",
        "confirm_password" to "new-password",
      ),
      fields(encoded),
    )
  }

  @Test
  fun `the communication preview request uses the api contract field names`() {
    val encoded = apiJson.encodeToString(
      RemoteCommunicationPreviewRequest(
        subject = "Fatura disponível",
        body = "Olá, sua fatura está pronta.",
      )
    )

    assertEquals(
      mapOf("subject" to "Fatura disponível", "body" to "Olá, sua fatura está pronta."),
      fields(encoded),
    )
  }

  @Test
  fun `a contact input carries only the name and the email`() {
    val recipient = BillingRecipient(
      id = RecipientID(rawValue = "contact-1"),
      name = "Bruno",
      email = "bruno@rentivo.com.br",
    )

    assertEquals(
      """{"name":"Bruno","email":"bruno@rentivo.com.br"}""",
      apiJson.encodeToString(RemoteContactInput.from(recipient)),
    )
  }

  @Test
  fun `an organization update without pix clears all three flattened fields`() {
    val encoded = apiJson.encodeToString(
      RemoteOrganizationUpdate.from(OrganizationDraft(name = "Horizonte", pix = null))
    )

    assertEquals(
      """{"name":"Horizonte","pix_key":"","pix_merchant_name":"","pix_merchant_city":""}""",
      encoded,
    )
  }

  @Test
  fun `an organization update with pix writes all three flattened fields`() {
    val encoded = apiJson.encodeToString(
      RemoteOrganizationUpdate.from(
        OrganizationDraft(
          name = "Horizonte",
          pix = PixConfiguration(key = "k", merchantName = "n", merchantCity = "c"),
        )
      )
    )

    assertEquals(
      """{"name":"Horizonte","pix_key":"k","pix_merchant_name":"n","pix_merchant_city":"c"}""",
      encoded,
    )
  }

  @Test
  fun `theme values round-trip through their snake_case wire names`() {
    val encoded = apiJson.encodeToString(RemoteThemeValues.from(ThemeValues.sunset))

    val decoded = apiJson.decodeFromString<RemoteThemeValues>(encoded)
    assertEquals("Playfair Display", encoded.let { apiJson.parseToJsonElement(it) }
      .jsonObject["header_font"]!!.jsonPrimitive.content)
    assertEquals(ThemeValues.sunset, decoded.toDomain())
  }

  @Test
  fun `an unknown theme font falls back instead of failing the decode`() {
    val decoded = apiJson.decodeFromString<RemoteThemeValues>(
      """{"header_font":"Comic Sans","text_font":"Papyrus","primary":"#000000",""" +
        """"primary_light":"#FFFFFF","secondary":"#111111","secondary_dark":"#222222",""" +
        """"text_color":"#333333","text_contrast":"#FFFFFF"}"""
    ).toDomain()

    assertEquals(app.rentivo.domain.ThemeFont.MONTSERRAT, decoded.headerFont)
    assertEquals(app.rentivo.domain.ThemeFont.OPEN_SANS, decoded.textFont)
  }

  @Test
  fun `the ULID gate accepts Crockford base32 of exactly 26 characters`() {
    assertEquals(true, isULID("01ARZ3NDEKTSV4RRFFQ69G5FAV"))
    // A client-minted UUID is 36 characters and carries hyphens and lowercase.
    assertEquals(false, isULID("6a3f2b1c-0d4e-4f5a-8b9c-0d1e2f3a4b5c"))
    // Crockford base32 excludes I, L, O and U.
    assertEquals(false, isULID("01ARZ3NDEKTSV4RRFFQ69G5FAU"))
    assertEquals(false, isULID("01ARZ3NDEKTSV4RRFFQ69G5FA"))
  }
}
