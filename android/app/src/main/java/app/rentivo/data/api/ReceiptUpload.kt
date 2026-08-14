package app.rentivo.data.api

import app.rentivo.data.ReceiptCaptureStore
import app.rentivo.domain.DemoError
import app.rentivo.domain.FileUpload
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The receipt contract the API enforces, restated on the client so a rejected upload is explained
 * here instead of surfacing as a generic failure.
 *
 * The server stores only these three media types and silently skips anything else, so an
 * unannounced HEIC — what many photo pickers hand over, and what an OEM camera in HEIF mode
 * writes even into a `.jpg` destination — would reach the user as "nothing happened". Mirrors
 * `ALLOWED_RECEIPT_TYPES` in `backend/rentivo/models/receipt.py`.
 */
val ACCEPTED_RECEIPT_MEDIA_TYPES: Set<String> =
  setOf("application/pdf", "image/jpeg", "image/png")

/** Mirrors `MAX_RECEIPT_SIZE` in `backend/rentivo/models/receipt.py`. */
const val MAX_RECEIPT_UPLOAD_BYTES: Int = 10 * 1024 * 1024

/** What everything not already accepted is re-encoded to before it is uploaded. */
const val JPEG_MEDIA_TYPE: String = "image/jpeg"

/** Shown when the file is over the server's limit; names the limit so the user can act on it. */
const val RECEIPT_TOO_LARGE_MESSAGE: String = "O comprovante excede o limite de 10 MB."

const val RECEIPT_EMPTY_MESSAGE: String = "O comprovante está vazio."

fun receiptSkippedMessage(reasons: List<String>): String = reasons.joinToString(" ") { reason ->
  when (reason) {
    "unsupported_mime" -> "Formato não aceito (use PDF, JPEG ou PNG)."
    "empty_file" -> RECEIPT_EMPTY_MESSAGE
    "size_limit_exceeded" -> RECEIPT_TOO_LARGE_MESSAGE
    else -> "O servidor recusou o comprovante."
  }
}

/** Shown when an image in an unsupported format could not be re-encoded to JPEG. */
const val RECEIPT_UNSUPPORTED_MESSAGE: String =
  "Não foi possível usar este arquivo como comprovante. Envie um PDF, JPEG ou PNG."

/** What has to happen to a file before it can be sent as a receipt. */
enum class ReceiptMediaDecision {
  /** The API stores this media type as-is. */
  ACCEPT,

  /** Anything else: re-encode to JPEG, or fail with [RECEIPT_UNSUPPORTED_MESSAGE]. */
  TRANSCODE_TO_JPEG,
}

/**
 * The media type without its parameters and in lower case, or null when there is nothing usable.
 * `image/JPEG; charset=binary` and `image/jpeg` are the same type as far as the contract goes.
 */
fun normalizedMediaType(mediaType: String?): String? = mediaType
  ?.substringBefore(';')
  ?.trim()
  ?.lowercase()
  ?.takeIf { it.isNotEmpty() }

/** Whether [mediaType] is one the API stores as-is. */
fun isAcceptedReceiptMediaType(mediaType: String?): Boolean =
  normalizedMediaType(mediaType) in ACCEPTED_RECEIPT_MEDIA_TYPES

/** [ReceiptMediaDecision] for [mediaType]; an absent or unknown type is transcoded, not trusted. */
fun receiptMediaDecision(mediaType: String?): ReceiptMediaDecision =
  if (isAcceptedReceiptMediaType(mediaType)) {
    ReceiptMediaDecision.ACCEPT
  } else {
    ReceiptMediaDecision.TRANSCODE_TO_JPEG
  }

/** Whether [byteCount] is over what the API accepts. */
fun exceedsReceiptSizeLimit(byteCount: Int): Boolean = byteCount > MAX_RECEIPT_UPLOAD_BYTES

/**
 * Returns [upload] when it fits the server's limit and throws PT-BR copy naming the limit when it
 * does not, so an oversized receipt is refused before a pointless multipart round-trip.
 */
fun requireReceiptWithinSizeLimit(upload: FileUpload): FileUpload {
  if (upload.byteCount == 0) throw DemoError(RECEIPT_EMPTY_MESSAGE)
  if (exceedsReceiptSizeLimit(upload.byteCount)) throw DemoError(RECEIPT_TOO_LARGE_MESSAGE)
  return upload
}

/**
 * The media type [bytes] actually are, read from their leading bytes, or null when they match none
 * of the formats a receipt can plausibly be.
 *
 * Needed because the camera contract reports only success or failure: the app names the
 * destination `.jpg`, but an OEM camera in HEIF mode writes HEIF into it anyway, and labelling that
 * `image/jpeg` is a mislabel the server discovers only when it merges receipts into a PDF.
 */
fun sniffImageMediaType(bytes: ByteArray): String? = when {
  bytes.startsWith(JPEG_MAGIC) -> JPEG_MEDIA_TYPE
  bytes.startsWith(PNG_MAGIC) -> "image/png"
  bytes.startsWith(PDF_MAGIC) -> "application/pdf"
  isHeif(bytes) -> HEIF_MEDIA_TYPE
  else -> null
}

private val JPEG_MAGIC = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())
private val PNG_MAGIC =
  byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
private val PDF_MAGIC = "%PDF-".toByteArray(Charsets.US_ASCII)
private const val HEIF_MEDIA_TYPE = "image/heif"

/** ISO base-media brands an HEIF still is published under; `heic`/`heix` are the common ones. */
private val HEIF_BRANDS =
  setOf("heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs", "mif1", "msf1")

private const val FTYP_BOX_OFFSET = 4
private const val BRAND_OFFSET = 8
private const val BRAND_END = 12

/**
 * An ISO base-media file declares its type in the `ftyp` box that opens it: four bytes of size,
 * the literal `ftyp`, then the major brand. Only the still-image brands count as a receipt.
 */
private fun isHeif(bytes: ByteArray): Boolean {
  if (bytes.size < BRAND_END) return false
  val box = String(bytes, FTYP_BOX_OFFSET, 4, Charsets.US_ASCII)
  if (box != "ftyp") return false
  return String(bytes, BRAND_OFFSET, BRAND_END - BRAND_OFFSET, Charsets.US_ASCII).lowercase() in
    HEIF_BRANDS
}

private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
  if (size < prefix.size) return false
  return prefix.indices.all { this[it] == prefix[it] }
}

/**
 * The name a re-encoded image is uploaded under: the generated, timestamped `comprovante-*.jpg`
 * rather than the source's own name, which would otherwise claim an extension the bytes no longer
 * have (`IMG_0001.HEIC` for JPEG data).
 */
fun transcodedReceiptFilename(): String = ReceiptCaptureStore.captureFilename()

/**
 * Reads a finished camera capture into a [FileUpload].
 *
 * Unlike a picked document, a capture needs no resolver round-trip: the app named the file, so the
 * filename is already known. The media type is sniffed rather than assumed, because the camera app
 * — not this one — chose the encoding. An empty file means the camera reported success without
 * writing anything, which would otherwise reach the API as a zero-byte receipt.
 *
 * Suspends on [ioDispatcher] because reading the photo is blocking and the caller is a picker
 * callback running on the main dispatcher.
 */
suspend fun fileUploadFromCapture(
  file: File,
  ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
): FileUpload = withContext(ioDispatcher) {
  val data = if (file.isFile) {
    file.inputStream().use { it.readAtMost(MAX_CLIENT_UPLOAD_BYTES) }
  } else {
    ByteArray(0)
  }
  if (data.isEmpty()) {
    throw DemoError("Não foi possível ler a foto capturada. Tente novamente.")
  }
  FileUpload(
    data = data,
    filename = file.name,
    mediaType = sniffImageMediaType(data) ?: UNKNOWN_MEDIA_TYPE,
  )
}

private const val UNKNOWN_MEDIA_TYPE = "application/octet-stream"
