package app.rentivo.data

import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Owns the on-disk lifecycle of the photos the camera writes when a receipt is captured.
 *
 * The camera contract hands the picture back through a URI the app supplies, so the app has to
 * create the destination itself. Captures land in a dedicated cache subdirectory — the one
 * `res/xml/file_paths.xml` exposes to the FileProvider — instead of the cache root, so a capture
 * can never be confused with a downloaded document and the whole batch can be cleared at once.
 *
 * Pure JVM on purpose, like [DownloadedFileStore]: the caller supplies the directory (in
 * production, a subdirectory of the app's cache dir), so this class and its tests never need an
 * Android context.
 */
class ReceiptCaptureStore(val directory: File) {

  /**
   * Creates the captures directory if needed and returns the file the camera should write to.
   *
   * The name is the one the receipt ends up carrying in the bill's list — the camera has no
   * document name to offer — so it is PT-BR and timestamped rather than a random identifier.
   */
  fun makeDestination(
    instant: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
  ): File {
    directory.mkdirs()
    return File(directory, captureFilename(instant = instant, zone = zone))
  }

  /**
   * Removes every capture this store produced, so no photo taken during an authenticated session
   * outlives it. Best effort, like [DownloadedFileStore.purge]: purging a directory that no longer
   * exists is a no-op.
   */
  fun purge() {
    directory.deleteRecursively()
  }

  companion object {
    /**
     * Name of the cache subdirectory holding camera captures. It must stay in sync with the
     * `captures` `cache-path` entry of `res/xml/file_paths.xml`, or the camera app cannot be
     * granted write access to the destination. `FileProviderPathsTest` pins the two together.
     */
    const val DIRECTORY_NAME: String = "RentivoCaptures"

    private const val FILENAME_PREFIX = "comprovante"
    private const val FILENAME_EXTENSION = "jpg"
    private val filenameTimestamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")

    /**
     * The local-time filename a generated receipt carries, e.g. `comprovante-20260809-143012.jpg`.
     *
     * Used for camera destinations and, in `app.rentivo.data.api`, for an image the app had to
     * re-encode: neither has a document name of its own, and both end up as JPEG.
     */
    fun captureFilename(
      instant: Instant = Instant.now(),
      zone: ZoneId = ZoneId.systemDefault(),
    ): String {
      val timestamp = filenameTimestamp.format(instant.atZone(zone))
      return "$FILENAME_PREFIX-$timestamp.$FILENAME_EXTENSION"
    }

    /**
     * Removes one capture once it has been uploaded — or once the camera returned without one.
     * Best effort: a file the OS already reclaimed from the cache is not a failure worth
     * surfacing, and neither is one the camera never created.
     */
    fun remove(file: File) {
      runCatching { file.delete() }
    }
  }
}
