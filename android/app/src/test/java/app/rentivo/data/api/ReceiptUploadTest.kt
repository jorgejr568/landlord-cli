package app.rentivo.data.api

import app.rentivo.domain.DemoError
import app.rentivo.domain.FileUpload
import java.io.ByteArrayInputStream
import java.io.File
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun bytes(vararg values: Int): ByteArray =
  ByteArray(values.size) { values[it].toByte() }

private val jpegBytes = bytes(0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10)
private val pngBytes = bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00)

/** The `ftyp` box a HEIF still opens with: box size, the literal `ftyp`, then the brand. */
private fun isoBaseMedia(brand: String): ByteArray =
  bytes(0x00, 0x00, 0x00, 0x18) + "ftyp$brand".toByteArray(Charsets.US_ASCII)

private fun makeIsolatedDirectory(): File = File(
  System.getProperty("java.io.tmpdir"),
  "RentivoCapturesTests-${UUID.randomUUID()}",
).also { it.mkdirs() }

// The reads run on the test scheduler instead of a real IO pool, so a capture is fully read before
// the assertions look at it.
@OptIn(ExperimentalCoroutinesApi::class)
class ReceiptUploadTest {

  @Test
  fun `the client contract mirrors what the API stores`() {
    assertEquals(setOf("application/pdf", "image/jpeg", "image/png"), ACCEPTED_RECEIPT_MEDIA_TYPES)
    assertEquals(10 * 1024 * 1024, MAX_RECEIPT_UPLOAD_BYTES)
  }

  @Test
  fun `media types are compared without parameters or case`() {
    assertEquals("image/jpeg", normalizedMediaType("Image/JPEG; charset=binary"))
    assertEquals("application/pdf", normalizedMediaType("  application/pdf  "))
    assertNull(normalizedMediaType(null))
    assertNull(normalizedMediaType("   "))
    assertTrue(isAcceptedReceiptMediaType("IMAGE/PNG"))
  }

  @Test
  fun `accepted types go as-is and everything else is transcoded`() {
    for (accepted in listOf("application/pdf", "image/jpeg", "image/png", "image/JPEG; q=1")) {
      assertEquals(ReceiptMediaDecision.ACCEPT, receiptMediaDecision(accepted))
    }
    for (rejected in listOf("image/heic", "image/heif", "image/webp", "image/gif", null, "")) {
      assertEquals(ReceiptMediaDecision.TRANSCODE_TO_JPEG, receiptMediaDecision(rejected))
    }
  }

  @Test
  fun `the sniffer reads the format from the leading bytes`() {
    assertEquals("image/jpeg", sniffImageMediaType(jpegBytes))
    assertEquals("image/png", sniffImageMediaType(pngBytes))
    assertEquals("application/pdf", sniffImageMediaType("%PDF-1.4".toByteArray()))
    for (brand in listOf("heic", "heix", "mif1", "HEIC")) {
      assertEquals("image/heif", sniffImageMediaType(isoBaseMedia(brand)))
    }
  }

  @Test
  fun `the sniffer stays silent on formats it does not know`() {
    assertNull(sniffImageMediaType(ByteArray(0)))
    assertNull(sniffImageMediaType(bytes(0xFF, 0xD8)))
    assertNull(sniffImageMediaType(isoBaseMedia("qt  ")))
    assertNull(sniffImageMediaType("RIFF????WEBP".toByteArray()))
  }

  @Test
  fun `a HEIF still is caught even when the file is named jpg`() {
    // The camera contract only reports success, so an OEM camera in HEIF mode would otherwise be
    // uploaded as image/jpeg and silently skipped by the server.
    assertEquals(
      ReceiptMediaDecision.TRANSCODE_TO_JPEG,
      receiptMediaDecision(sniffImageMediaType(isoBaseMedia("heic"))),
    )
  }

  @Test
  fun `an upload over the server limit is refused with PT-BR copy naming the limit`() {
    assertFalse(exceedsReceiptSizeLimit(MAX_RECEIPT_UPLOAD_BYTES))
    assertTrue(exceedsReceiptSizeLimit(MAX_RECEIPT_UPLOAD_BYTES + 1))

    val oversized = FileUpload(
      data = ByteArray(MAX_RECEIPT_UPLOAD_BYTES + 1),
      filename = "comprovante.pdf",
      mediaType = "application/pdf",
    )
    val thrown = runCatching { requireReceiptWithinSizeLimit(oversized) }.exceptionOrNull()

    assertEquals(DemoError(RECEIPT_TOO_LARGE_MESSAGE), thrown)
    assertEquals("O comprovante excede o limite de 10 MB.", RECEIPT_TOO_LARGE_MESSAGE)
  }

  @Test
  fun `an upload at the limit passes through unchanged`() {
    val upload = FileUpload(
      data = jpegBytes,
      filename = "comprovante.jpg",
      mediaType = "image/jpeg",
    )

    assertTrue(upload === requireReceiptWithinSizeLimit(upload))
  }

  @Test
  fun `an empty receipt is rejected locally`() {
    val empty = FileUpload(data = ByteArray(0), filename = "vazio.pdf", mediaType = "application/pdf")

    val thrown = runCatching { requireReceiptWithinSizeLimit(empty) }.exceptionOrNull()

    assertEquals(DemoError(RECEIPT_EMPTY_MESSAGE), thrown)
  }

  @Test
  fun `upload response decodes every skipped reason with localized detail`() {
    val response = apiJson.decodeFromString<RemoteReceiptUpload>(
      """{"items":[],"attached":0,"skipped":3,"total_bytes":0,"skipped_reasons":["unsupported_mime","empty_file","size_limit_exceeded"]}"""
    )

    assertEquals(3, response.skippedReasons.size)
    assertEquals(
      "Formato não aceito (use PDF, JPEG ou PNG). O comprovante está vazio. O comprovante excede o limite de 10 MB.",
      receiptSkippedMessage(response.skippedReasons),
    )
  }

  @Test
  fun `the bounded reader rejects a stream before allocating beyond the API limit`() {
    val error = runCatching {
      ByteArrayInputStream(ByteArray(5)).readAtMost(maxBytes = 4)
    }.exceptionOrNull()

    assertEquals(DemoError(UPLOAD_TOO_LARGE_MESSAGE), error)
    assertEquals(10 * 1024 * 1024, MAX_CLIENT_UPLOAD_BYTES)
  }

  @Test
  fun `a re-encoded image is named like a capture rather than after its source`() {
    val name = transcodedReceiptFilename()

    assertTrue(name.startsWith("comprovante-"))
    assertTrue(name.endsWith(".jpg"))
  }

  @Test
  fun `a capture becomes an upload carrying its own name and its actual media type`() = runTest {
    val directory = makeIsolatedDirectory()
    try {
      val jpeg = File(directory, "comprovante-20260809-173012.jpg")
      jpeg.writeBytes(jpegBytes)
      val heif = File(directory, "comprovante-20260809-173013.jpg")
      heif.writeBytes(isoBaseMedia("heic"))

      val fromJpeg = fileUploadFromCapture(
        file = jpeg,
        ioDispatcher = UnconfinedTestDispatcher(testScheduler),
      )
      val fromHeif = fileUploadFromCapture(
        file = heif,
        ioDispatcher = UnconfinedTestDispatcher(testScheduler),
      )

      assertEquals("comprovante-20260809-173012.jpg", fromJpeg.filename)
      assertEquals("image/jpeg", fromJpeg.mediaType)
      assertEquals(jpegBytes.size, fromJpeg.byteCount)
      // Named .jpg, but the bytes say otherwise: the label follows the bytes.
      assertEquals("image/heif", fromHeif.mediaType)
    } finally {
      directory.deleteRecursively()
    }
  }

  @Test
  fun `a capture in no recognizable format is left for the transcoder to judge`() = runTest {
    val directory = makeIsolatedDirectory()
    try {
      val unknown = File(directory, "comprovante-20260809-173014.jpg")
      unknown.writeBytes("RIFF????WEBP".toByteArray())

      val upload = fileUploadFromCapture(
        file = unknown,
        ioDispatcher = UnconfinedTestDispatcher(testScheduler),
      )

      assertEquals("application/octet-stream", upload.mediaType)
      assertEquals(ReceiptMediaDecision.TRANSCODE_TO_JPEG, receiptMediaDecision(upload.mediaType))
    } finally {
      directory.deleteRecursively()
    }
  }

  @Test
  fun `a camera that wrote nothing surfaces PT-BR copy instead of an empty receipt`() = runTest {
    val directory = makeIsolatedDirectory()
    try {
      val empty = File(directory, "comprovante-vazio.jpg")
      empty.writeBytes(ByteArray(0))
      val missing = File(directory, "comprovante-nao-escrito.jpg")

      for (file in listOf(empty, missing)) {
        val thrown = runCatching {
          fileUploadFromCapture(
            file = file,
            ioDispatcher = UnconfinedTestDispatcher(testScheduler),
          )
        }.exceptionOrNull()

        assertNotNull(thrown)
        assertTrue(thrown is DemoError)
        assertTrue(thrown!!.message!!.startsWith("Não foi possível ler a foto"))
      }
    } finally {
      directory.deleteRecursively()
    }
  }
}
