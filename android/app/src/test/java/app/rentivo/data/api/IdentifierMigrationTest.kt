package app.rentivo.data.api

import app.rentivo.domain.BillingID
import app.rentivo.domain.FileUpload
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.WorkspaceID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Server identifiers stay opaque strings across the wire boundary: the API mints ULIDs today and
 * public slugs elsewhere, so nothing may assume UUID syntax.
 */
class IdentifierMigrationTest {

  @Test
  fun `opaque identifiers do not require uuid parsing`() {
    assertEquals(
      "01K0RENTIVO7QVK5R9H5G2Z0AB",
      BillingID(rawValue = "01K0RENTIVO7QVK5R9H5G2Z0AB").rawValue,
    )
    assertEquals(
      "org_public_slug_like_value",
      OrganizationID(rawValue = "org_public_slug_like_value").rawValue,
    )
  }

  @Test
  fun `a file upload carries its actual bytes`() {
    val upload = FileUpload(
      data = byteArrayOf(0x25, 0x50, 0x44, 0x46),
      filename = "recibo.pdf",
      mediaType = "application/pdf",
    )

    assertEquals(4, upload.byteCount)
  }

  @Test
  fun `a personal api key grant uses the literal personal workspace`() {
    assertEquals("personal", WorkspaceID.personal.rawValue)
  }
}
