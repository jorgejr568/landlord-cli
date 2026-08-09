package app.rentivo.data

import app.rentivo.domain.DownloadedFile
import java.io.File
import java.util.UUID

/**
 * Owns the on-disk lifecycle of the files the API client's download calls produce.
 *
 * Downloads land in a dedicated subdirectory rather than in the cache root itself, so the app can
 * remove exactly its own downloads without touching scratch files other components write there.
 * Outside the `data` layer only [remove] is needed.
 *
 * Pure JVM on purpose: the caller supplies the directory (in production, a subdirectory of the
 * app's cache dir), so this class and its tests never need an Android context.
 */
class DownloadedFileStore(val directory: File) {

  /**
   * Creates the downloads directory if needed and returns a collision-free destination carrying
   * [pathExtension], which is what lets the share sheet and the receiving app infer the type.
   */
  fun makeDestination(pathExtension: String): File {
    directory.mkdirs()
    val name = if (pathExtension.isEmpty()) {
      UUID.randomUUID().toString()
    } else {
      "${UUID.randomUUID()}.$pathExtension"
    }
    return File(directory, name)
  }

  /**
   * Removes every file this store produced, so nothing an authenticated session downloaded
   * outlives that session. Best effort: purging a directory that no longer exists is a no-op.
   */
  fun purge() {
    directory.deleteRecursively()
  }

  companion object {
    /**
     * Removes one downloaded file. Best effort: a file the OS already reclaimed from the cache on
     * its own schedule is not a failure worth surfacing to the caller.
     */
    fun remove(file: DownloadedFile) {
      runCatching { file.file.delete() }
    }
  }
}
