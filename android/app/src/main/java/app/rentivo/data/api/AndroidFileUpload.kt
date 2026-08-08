package app.rentivo.data.api

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import app.rentivo.domain.FileUpload
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileNotFoundException

/**
 * Reads a user-picked document into a [FileUpload].
 *
 * Android counterpart of the iOS `FileUpload.from(url:)`. A `content://` URI is not a file path, so
 * the three pieces come from the resolver instead of the path components: bytes from the opened
 * stream, the display name from [OpenableColumns], and the media type from the provider — falling
 * back to the filename extension and finally to `application/octet-stream`, which is what the iOS
 * version does for an unknown extension.
 *
 * Suspends on [ioDispatcher]: both the provider query and reading the whole document are blocking,
 * and every caller is a picker callback running on the main dispatcher.
 *
 * Throws (typically [FileNotFoundException] or [SecurityException]) when the URI cannot be opened,
 * mirroring the iOS behaviour for a missing file.
 */
suspend fun fileUploadFromUri(
  resolver: ContentResolver,
  uri: Uri,
  ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
): FileUpload = withContext(ioDispatcher) {
  val mediaType = resolver.getType(uri)
  val filename = displayName(resolver, uri, mediaType)
  val data = resolver.openInputStream(uri)?.use { it.readBytes() }
    ?: throw FileNotFoundException("Não foi possível abrir o arquivo selecionado.")
  FileUpload(
    data = data,
    filename = filename,
    mediaType = mediaType ?: mediaTypeFromExtension(filename) ?: DEFAULT_MEDIA_TYPE,
  )
}

private const val DEFAULT_MEDIA_TYPE = "application/octet-stream"
private const val FALLBACK_FILENAME = "arquivo"

/**
 * The provider's display name, the URI's last path segment, or a generic name. The generic name
 * carries an extension derived from [mediaType] when the provider declared one, because the server
 * stores what we send and the extension is all the web app has to render the right file icon.
 */
private fun displayName(resolver: ContentResolver, uri: Uri, mediaType: String?): String {
  val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
  val name = resolver.query(uri, projection, null, null, null)?.use { cursor ->
    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
    if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
  }
  return name?.takeIf { it.isNotBlank() }
    ?: uri.lastPathSegment?.takeIf { it.isNotBlank() }
    ?: fallbackFilename(mediaType)
}

private fun fallbackFilename(mediaType: String?): String {
  val extension = mediaType
    ?.substringBefore(";")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it.lowercase()) }
  return if (extension.isNullOrEmpty()) FALLBACK_FILENAME else "$FALLBACK_FILENAME.$extension"
}

private fun mediaTypeFromExtension(filename: String): String? {
  val extension = filename.substringAfterLast('.', "")
  if (extension.isEmpty()) return null
  return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
}
