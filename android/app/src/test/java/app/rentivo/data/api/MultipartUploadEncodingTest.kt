package app.rentivo.data.api

import app.rentivo.domain.BillID
import app.rentivo.domain.BillingID
import app.rentivo.domain.FileUpload
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Multipart body encoding. `multipartBody`/`sanitizedFilename` are exercised through the two
 * upload entry points (`addReceipt`, `addAttachment`) with a recording dispatcher, so the bytes
 * asserted here are exactly the bytes the server would receive.
 */
class MultipartUploadEncodingTest {

  private val server = MockWebServer()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  private suspend fun authenticatedStore(): APIRentivoStore {
    val store = APIRentivoStore(liveClient(server))
    assertNotNull(store.restoreSession())
    return store
  }

  @Test
  fun `a receipt upload uses a Rentivo boundary and sanitizes an injecting filename`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "POST /api/v1/billings/billing-1/bills/bill-1/receipts") {
        jsonResponse(
          """{"items":[{"uuid":"receipt-1","filename":"notainjetada.pdf",""" +
            """"content_type":"application/pdf","file_size":8,"sort_order":0}]}"""
        )
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()
    // A filename crafted to break out of the quoted `filename="..."` attribute (or the header line
    // entirely) if it were sent unsanitized: an embedded quote plus a CRLF.
    val upload = FileUpload(
      data = "%PDF-1.4".toByteArray(),
      filename = "nota\r\ninjetada\".pdf",
      mediaType = "application/pdf",
    )

    val receipt = store.addReceipt(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      upload = upload,
    )

    assertEquals("receipt-1", receipt.id.rawValue)
    val call = dispatcher.callTo("POST /api/v1/billings/billing-1/bills/bill-1/receipts")!!
    val contentType = call.headers["Content-Type"]!!
    assertTrue(contentType.startsWith("multipart/form-data; boundary=RentivoBoundary-"))
    val boundary = contentType.removePrefix("multipart/form-data; boundary=")

    val body = call.bodyText
    // Opens and closes with the exact boundary markers multipart/form-data requires.
    assertTrue(body.startsWith("--$boundary\r\n"))
    assertTrue(body.endsWith("--$boundary--\r\n"))
    // The dangerous characters never reach the header line...
    assertFalse(body.contains("nota\r\ninjetada\""))
    // ...but the sanitized filename is still the attribute value, and the field name and content
    // type are what the upload call asked for.
    assertTrue(
      body.contains(
        """Content-Disposition: form-data; name="receipt_files"; filename="notainjetada.pdf""""
      )
    )
    assertTrue(body.contains("Content-Type: application/pdf"))
    assertTrue(body.contains("%PDF-1.4"))
    // A receipt upload has no separate `name` text part.
    assertFalse(body.contains("""name="name""""))
  }

  @Test
  fun `an attachment upload sends a top-level name field alongside the file part`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "POST /api/v1/billings/billing-1/attachments") {
        jsonResponse(
          """{"uuid":"attachment-1","name":"contrato-locacao.pdf",""" +
            """"content_type":"application/pdf","file_size":8}"""
        )
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()

    val attachment = store.addAttachment(
      billingID = BillingID(rawValue = "billing-1"),
      upload = FileUpload(
        data = "contrato".toByteArray(),
        filename = "contrato-locacao.pdf",
        mediaType = "application/pdf",
      ),
    )

    assertEquals("attachment-1", attachment.id.rawValue)
    assertEquals("application/pdf", attachment.mediaType)
    assertEquals(8, attachment.byteCount)
    val body = dispatcher.bodyOf("POST /api/v1/billings/billing-1/attachments")
    assertTrue(body.contains("""Content-Disposition: form-data; name="name""""))
    assertTrue(body.contains("\r\n\r\ncontrato-locacao.pdf\r\n"))
    assertTrue(body.contains("""name="file"; filename="contrato-locacao.pdf""""))
  }

  @Test
  fun `an upload response with no items at all is an invalid response`() = runTest {
    server.routeWithSession { jsonResponse("""{"items":[]}""") }
    val store = authenticatedStore()

    val error = runCatching {
      store.addReceipt(
        billingID = BillingID(rawValue = "billing-1"),
        billID = BillID(rawValue = "bill-1"),
        upload = FileUpload(
          data = ByteArray(0),
          filename = "vazio.pdf",
          mediaType = "application/pdf",
        ),
      )
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }

  @Test
  fun `the filename sanitizer strips every header-injection character`() {
    assertEquals(
      "notainjetada.pdf",
      sanitizedFilename("nota\r\ninjetada\".pdf"),
    )
    assertEquals("ab.pdf", sanitizedFilename("a\rb\n.pdf"))
    assertEquals("contrato-locação.pdf", sanitizedFilename("contrato-locação.pdf"))
  }

  @Test
  fun `binary upload payloads survive the multipart framing byte for byte`() {
    val bytes = byteArrayOf(0x00, 0x7F.toByte(), 0xFF.toByte(), 0x25, 0x50)
    val body = multipartBody(
      boundary = "RentivoBoundary-test",
      name = null,
      files = listOf(
        MultipartFile(
          field = "file",
          upload = FileUpload(
            data = bytes,
            filename = "raw.bin",
            mediaType = "application/octet-stream",
          ),
        )
      ),
    )

    val header = "--RentivoBoundary-test\r\n" +
      "Content-Disposition: form-data; name=\"file\"; filename=\"raw.bin\"\r\n" +
      "Content-Type: application/octet-stream\r\n\r\n"
    val start = header.toByteArray().size
    assertEquals(
      bytes.toList(),
      body.copyOfRange(start, start + bytes.size).toList(),
    )
  }
}
