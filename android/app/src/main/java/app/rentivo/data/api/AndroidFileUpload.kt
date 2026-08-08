package app.rentivo.data.api

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import app.rentivo.domain.FileUpload
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
 * Throws (typically [FileNotFoundException] or [SecurityException]) when the URI cannot be opened,
 * mirroring the iOS behaviour for a missing file.
 */
fun fileUploadFromUri(resolver: ContentResolver, uri: Uri): FileUpload {
  val filename = displayName(resolver, uri)
  val mediaType = resolver.getType(uri)
    ?: mediaTypeFromExtension(filename)
    ?: DEFAULT_MEDIA_TYPE
  val data = resolver.openInputStream(uri)?.use { it.readBytes() }
    ?: throw FileNotFoundException("Não foi possível abrir o arquivo selecionado.")
  return FileUpload(data = data, filename = filename, mediaType = mediaType)
}

private const val DEFAULT_MEDIA_TYPE = "application/octet-stream"
private const val FALLBACK_FILENAME = "arquivo"

private fun displayName(resolver: ContentResolver, uri: Uri): String {
  val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
  val name = resolver.query(uri, projection, null, null, null)?.use { cursor ->
    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
    if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
  }
  return name?.takeIf { it.isNotBlank() }
    ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
    ?: FALLBACK_FILENAME
}

private fun mediaTypeFromExtension(filename: String): String? {
  val extension = filename.substringAfterLast('.', "")
  if (extension.isEmpty()) return null
  return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
}
