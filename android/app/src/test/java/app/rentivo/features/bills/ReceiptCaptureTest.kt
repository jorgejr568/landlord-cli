package app.rentivo.features.bills

import app.rentivo.domain.DemoError
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Every test owns its own directory, so one test's cleanup can never delete a file another test is
// still asserting on.
private fun makeIsolatedCaptureStore(): ReceiptCaptureStore = ReceiptCaptureStore(
  directory = File(
    System.getProperty("java.io.tmpdir"),
    "RentivoCapturesTests-${UUID.randomUUID()}",
  )
)

private val instant = Instant.parse("2026-08-09T17:30:12Z")

// The reads run on the test scheduler instead of a real IO pool, so a capture is fully read before
// the assertions look at it.
@OptIn(ExperimentalCoroutinesApi::class)
class ReceiptCaptureTest {

  @Test
  fun `the capture filename is timestamped in the given zone`() {
    val name = ReceiptCaptureStore.captureFilename(
      instant = instant,
      zone = ZoneId.of("America/Sao_Paulo"),
    )

    assertEquals("comprovante-20260809-143012.jpg", name)
  }

  @Test
  fun `the capture filename follows the zone rather than UTC`() {
    val name = ReceiptCaptureStore.captureFilename(instant = instant, zone = ZoneId.of("UTC"))

    assertEquals("comprovante-20260809-173012.jpg", name)
  }

  @Test
  fun `makeDestination creates the captures directory and names the file for the camera`() {
    val store = makeIsolatedCaptureStore()
    try {
      assertFalse(store.directory.exists())

      val destination = store.makeDestination(instant = instant, zone = ZoneId.of("UTC"))

      assertTrue(store.directory.isDirectory)
      assertEquals(store.directory.canonicalPath, destination.parentFile!!.canonicalPath)
      assertEquals("comprovante-20260809-173012.jpg", destination.name)
      // The camera creates the file itself: only the directory has to exist up front.
      assertFalse(destination.exists())
    } finally {
      store.directory.deleteRecursively()
    }
  }

  @Test
  fun `a capture becomes an upload carrying its own name and the JPEG media type`() = runTest {
    val store = makeIsolatedCaptureStore()
    try {
      val destination = store.makeDestination(instant = instant, zone = ZoneId.of("UTC"))
      destination.writeBytes(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()))

      val upload = fileUploadFromCapture(
        file = destination,
        ioDispatcher = UnconfinedTestDispatcher(testScheduler),
      )

      assertEquals("comprovante-20260809-173012.jpg", upload.filename)
      assertEquals("image/jpeg", upload.mediaType)
      assertEquals(3, upload.byteCount)
    } finally {
      store.directory.deleteRecursively()
    }
  }

  @Test
  fun `a camera that wrote nothing surfaces PT-BR copy instead of an empty receipt`() = runTest {
    val store = makeIsolatedCaptureStore()
    try {
      val empty = store.makeDestination(instant = instant, zone = ZoneId.of("UTC"))
      empty.writeBytes(ByteArray(0))
      val missing = File(store.directory, "comprovante-nao-escrito.jpg")

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
      store.directory.deleteRecursively()
    }
  }

  @Test
  fun `remove deletes a capture and tolerates one the camera never created`() {
    val store = makeIsolatedCaptureStore()
    try {
      val destination = store.makeDestination(instant = instant, zone = ZoneId.of("UTC"))
      destination.writeBytes(byteArrayOf(1))

      ReceiptCaptureStore.remove(destination)
      assertFalse(destination.exists())

      // Second removal is a no-op rather than a failure.
      ReceiptCaptureStore.remove(destination)
      assertFalse(destination.exists())
    } finally {
      store.directory.deleteRecursively()
    }
  }
}
