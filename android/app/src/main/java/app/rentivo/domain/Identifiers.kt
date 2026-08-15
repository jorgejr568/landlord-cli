package app.rentivo.domain

import java.io.File

/**
 * Opaque server identifiers.
 *
 * Swift models these as one generic `ResourceID<Tag>` with phantom tags; Kotlin has no zero-cost
 * equivalent, so each identifier is its own inline value class over the same `rawValue` String.
 * The values stay opaque — never parse them as UUIDs.
 */
@JvmInline value class BillingID(val rawValue: String)

@JvmInline value class BillID(val rawValue: String)

@JvmInline value class BillingItemID(val rawValue: String)

@JvmInline value class BillLineItemID(val rawValue: String)

@JvmInline value class ReceiptID(val rawValue: String)

@JvmInline value class ExpenseID(val rawValue: String)

@JvmInline value class AttachmentID(val rawValue: String)

@JvmInline value class OrganizationID(val rawValue: String)

@JvmInline value class InvitationID(val rawValue: String)

@JvmInline value class APIKeyID(val rawValue: String)

@JvmInline value class PasskeyID(val rawValue: String)

@JvmInline value class CommunicationID(val rawValue: String)

@JvmInline value class RecipientID(val rawValue: String)

@JvmInline
value class WorkspaceID(val rawValue: String) {
  companion object {
    val personal = WorkspaceID(rawValue = "personal")
  }
}

/** Bytes staged for a multipart upload. */
class FileUpload(
  val data: ByteArray,
  val filename: String,
  val mediaType: String,
) {
  val byteCount: Int get() = data.size

  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is FileUpload) return false
    return data.contentEquals(other.data) &&
      filename == other.filename &&
      mediaType == other.mediaType
  }

  override fun hashCode(): Int {
    var result = data.contentHashCode()
    result = 31 * result + filename.hashCode()
    result = 31 * result + mediaType.hashCode()
    return result
  }

  override fun toString(): String =
    "FileUpload(filename=$filename, mediaType=$mediaType, byteCount=$byteCount)"
}

object AttachmentUploadRules {
  /** Mirrors `ALLOWED_ATTACHMENT_TYPES` in the backend billing attachment model. */
  val allowedMediaTypes: Set<String> = setOf("application/pdf", "image/jpeg", "image/png")

  /** Mirrors `MAX_ATTACHMENT_SIZE` in the backend billing attachment model. */
  const val maximumByteCount: Int = 10 * 1024 * 1024

  fun validated(upload: FileUpload): FileUpload {
    val mediaType = upload.mediaType.substringBefore(';').trim().lowercase()
    if (mediaType !in allowedMediaTypes) throw DemoError("Envie um arquivo PDF, JPEG ou PNG.")
    if (upload.byteCount == 0) throw DemoError("O arquivo selecionado está vazio.")
    if (upload.byteCount > maximumByteCount) {
      throw DemoError("O arquivo excede o limite de 10 MB.")
    }
    return FileUpload(data = upload.data, filename = upload.filename, mediaType = mediaType)
  }
}

/** A file the API layer wrote into the downloads directory owned by `DownloadedFileStore`. */
data class DownloadedFile(
  val file: File,
  val filename: String,
  val mediaType: String,
)
