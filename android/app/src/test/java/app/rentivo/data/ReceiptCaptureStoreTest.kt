package app.rentivo.data

import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

class ReceiptCaptureStoreTest {

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

  @Test
  fun `purge removes every capture left behind and tolerates a missing directory`() {
    val store = makeIsolatedCaptureStore()
    try {
      val leaked = store.makeDestination(instant = instant, zone = ZoneId.of("UTC"))
      leaked.writeBytes(byteArrayOf(1, 2, 3))
      assertTrue(leaked.exists())

      store.purge()

      assertFalse(leaked.exists())
      assertFalse(store.directory.exists())
      // Purging twice — a sign-out with nothing left to clear — is a no-op.
      store.purge()
      assertFalse(store.directory.exists())
    } finally {
      store.directory.deleteRecursively()
    }
  }
}
