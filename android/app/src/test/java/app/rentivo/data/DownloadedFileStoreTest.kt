package app.rentivo.data

import app.rentivo.domain.DownloadedFile
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Every test that writes a downloaded file injects its own directory, so a purge in one test can
// never delete a file another test is still asserting on.
private fun makeIsolatedDownloadsStore(): DownloadedFileStore = DownloadedFileStore(
  directory = File(
    System.getProperty("java.io.tmpdir"),
    "RentivoDownloadsTests-${UUID.randomUUID()}",
  )
)

class DownloadedFileStoreTest {

  @Test
  fun makeDestinationCreatesTheDirectoryAndKeepsThePathExtension() {
    val store = makeIsolatedDownloadsStore()
    try {
      assertFalse(store.directory.exists())

      val destination = store.makeDestination(pathExtension = "pdf")

      assertTrue(store.directory.isDirectory)
      assertEquals(store.directory.canonicalPath, destination.parentFile!!.canonicalPath)
      assertTrue(destination.name.endsWith(".pdf"))
      // Collision-free: two destinations never share a name.
      assertNotEquals(destination.name, store.makeDestination(pathExtension = "pdf").name)
    } finally {
      store.purge()
    }
  }

  @Test
  fun makeDestinationOmitsTheDotWhenThereIsNoExtension() {
    val store = makeIsolatedDownloadsStore()
    try {
      assertFalse(store.makeDestination(pathExtension = "").name.contains("."))
    } finally {
      store.purge()
    }
  }

  @Test
  fun removeDeletesASingleDownloadedFileAndToleratesAMissingOne() {
    val store = makeIsolatedDownloadsStore()
    try {
      val destination = store.makeDestination(pathExtension = "pdf")
      destination.writeBytes("%PDF-1.4".toByteArray())
      val file = DownloadedFile(
        file = destination,
        filename = "fatura.pdf",
        mediaType = "application/pdf",
      )

      DownloadedFileStore.remove(file)

      assertFalse(destination.exists())
      // The OS reclaims the cache directory on its own schedule, so removing an already-gone file
      // is expected and must stay silent rather than throw.
      DownloadedFileStore.remove(file)
      assertFalse(destination.exists())
    } finally {
      store.purge()
    }
  }

  @Test
  fun purgeRemovesTheWholeDownloadsDirectory() {
    val store = makeIsolatedDownloadsStore()
    val first = store.makeDestination(pathExtension = "pdf")
    first.writeBytes("%PDF-1.4".toByteArray())
    val second = store.makeDestination(pathExtension = "jpg")
    second.writeBytes(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()))

    store.purge()

    assertFalse(first.exists())
    assertFalse(second.exists())
    assertFalse(store.directory.exists())
    // Purging a directory that no longer exists is a no-op, not a failure.
    store.purge()
  }
}
