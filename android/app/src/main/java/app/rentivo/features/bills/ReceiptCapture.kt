package app.rentivo.features.bills

import app.rentivo.domain.DemoError
import app.rentivo.domain.FileUpload
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Owns the on-disk lifecycle of the photos the camera writes when a receipt is captured.
 *
 * The camera contract hands the picture back through a URI the app supplies, so the app has to
 * create the destination itself. Captures land in a dedicated cache subdirectory — the one
 * `res/xml/file_paths.xml` exposes to the FileProvider — instead of the cache root, so a capture
 * can never be confused with a downloaded document and the whole batch can be cleared at once.
 *
 * Pure JVM on purpose, like [app.rentivo.data.DownloadedFileStore]: the caller supplies the
 * directory (in production, a subdirectory of the app's cache dir), so this class and its tests
 * never need an Android context.
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

  companion object {
    /**
     * Name of the cache subdirectory holding camera captures. It must stay in sync with the
     * `captures` `cache-path` entry of `res/xml/file_paths.xml`, or the camera app cannot be
     * granted write access to the destination.
     */
    const val DIRECTORY_NAME: String = "RentivoCaptures"

    /** What the camera contract always writes, and what the upload is therefore labelled with. */
    const val MEDIA_TYPE: String = "image/jpeg"

    private const val FILENAME_PREFIX = "comprovante"
    private const val FILENAME_EXTENSION = "jpg"
    private val filenameTimestamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")

    /** The capture's local-time filename, e.g. `comprovante-20260809-143012.jpg`. */
    fun captureFilename(instant: Instant, zone: ZoneId): String {
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

/**
 * Reads a finished camera capture into a [FileUpload].
 *
 * Unlike a picked document, a capture needs no resolver round-trip: the app named the file and the
 * camera contract only ever writes JPEG, so both the filename and the media type are already
 * known. An empty file means the camera reported success without writing anything, which would
 * otherwise reach the API as a zero-byte receipt.
 *
 * Suspends on [ioDispatcher] because reading the photo is blocking and the caller is a picker
 * callback running on the main dispatcher.
 */
suspend fun fileUploadFromCapture(
  file: File,
  ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
): FileUpload = withContext(ioDispatcher) {
  val data = if (file.isFile) file.readBytes() else ByteArray(0)
  if (data.isEmpty()) {
    throw DemoError("Não foi possível ler a foto capturada. Tente novamente.")
  }
  FileUpload(
    data = data,
    filename = file.name,
    mediaType = ReceiptCaptureStore.MEDIA_TYPE,
  )
}
