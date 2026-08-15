import Foundation
import UniformTypeIdentifiers

public struct ResourceID<Tag>: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
  public let rawValue: String

  public var id: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum BillingIDTag: Sendable {}
public typealias BillingID = ResourceID<BillingIDTag>
public enum BillIDTag: Sendable {}
public typealias BillID = ResourceID<BillIDTag>
public enum BillingItemIDTag: Sendable {}
public typealias BillingItemID = ResourceID<BillingItemIDTag>
public enum BillLineItemIDTag: Sendable {}
public typealias BillLineItemID = ResourceID<BillLineItemIDTag>
public enum ReceiptIDTag: Sendable {}
public typealias ReceiptID = ResourceID<ReceiptIDTag>
public enum ExpenseIDTag: Sendable {}
public typealias ExpenseID = ResourceID<ExpenseIDTag>
public enum AttachmentIDTag: Sendable {}
public typealias AttachmentID = ResourceID<AttachmentIDTag>
public enum OrganizationIDTag: Sendable {}
public typealias OrganizationID = ResourceID<OrganizationIDTag>
public enum InvitationIDTag: Sendable {}
public typealias InvitationID = ResourceID<InvitationIDTag>
public enum APIKeyIDTag: Sendable {}
public typealias APIKeyID = ResourceID<APIKeyIDTag>
public enum PasskeyIDTag: Sendable {}
public typealias PasskeyID = ResourceID<PasskeyIDTag>
public enum CommunicationIDTag: Sendable {}
public typealias CommunicationID = ResourceID<CommunicationIDTag>
public enum RecipientIDTag: Sendable {}
public typealias RecipientID = ResourceID<RecipientIDTag>
public enum WorkspaceIDTag: Sendable {}
public typealias WorkspaceID = ResourceID<WorkspaceIDTag>

public extension ResourceID where Tag == WorkspaceIDTag {
  static let personal = Self(rawValue: "personal")
}

public struct FileUpload: Hashable, Sendable {
  public let data: Data
  public let filename: String
  public let mediaType: String

  public init(data: Data, filename: String, mediaType: String) {
    self.data = data
    self.filename = filename
    self.mediaType = mediaType
  }

  public var byteCount: Int { data.count }

  public static func from(url: URL, policy: FileUploadPolicy? = nil) throws -> Self {
    let filename = url.lastPathComponent
    let mediaType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
      ?? "application/octet-stream"
    if policy == .rentivoDocument {
      guard RentivoUploadPolicy.allowedMediaTypes.contains(mediaType.lowercased()) else {
        throw FileUploadValidationError.unsupportedType
      }
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard let fileSize = values.fileSize, fileSize <= RentivoUploadPolicy.maxByteCount else {
        throw FileUploadValidationError.tooLarge
      }
    }
    return try Self(data: Data(contentsOf: url), filename: filename, mediaType: mediaType)
  }

  /// Claims a document-picker URL and performs its metadata/data reads off the UI actor.
  public nonisolated static func fromSecurityScoped(
    url: URL, policy: FileUploadPolicy? = nil
  ) async throws -> Self {
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
    return try from(url: url, policy: policy)
  }
}

public enum FileUploadPolicy: Hashable, Sendable {
  case rentivoDocument
}

public enum RentivoUploadPolicy {
  public static let maxByteCount = 10 * 1024 * 1024
  public static let allowedMediaTypes: Set<String> = [
    "application/pdf", "image/jpeg", "image/png",
  ]
}

public enum FileUploadValidationError: Error, Equatable, Sendable {
  case unsupportedType
  case tooLarge
}

public enum AttachmentUploadRules {
  /// Mirrors `ALLOWED_ATTACHMENT_TYPES` in `backend/rentivo/models/billing_attachment.py`.
  public static let allowedMediaTypes: Set<String> = [
    "application/pdf", "image/jpeg", "image/png",
  ]

  /// Mirrors `MAX_ATTACHMENT_SIZE` in `backend/rentivo/models/billing_attachment.py`.
  public static let maxByteCount = 10 * 1024 * 1024

  public static func validated(_ upload: FileUpload) throws -> FileUpload {
    let mediaType = upload.mediaType
      .split(separator: ";", maxSplits: 1)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    guard allowedMediaTypes.contains(mediaType) else {
      throw DemoError(message: "Envie um arquivo PDF, JPEG ou PNG.")
    }
    guard upload.byteCount > 0 else {
      throw DemoError(message: "O arquivo selecionado está vazio.")
    }
    guard upload.byteCount <= maxByteCount else {
      throw DemoError(message: "O arquivo excede o limite de 10 MB.")
    }
    return FileUpload(data: upload.data, filename: upload.filename, mediaType: mediaType)
  }
}

public struct DownloadedFile: Hashable, Sendable {
  public let fileURL: URL
  public let filename: String
  public let mediaType: String

  public init(fileURL: URL, filename: String, mediaType: String) {
    self.fileURL = fileURL
    self.filename = filename
    self.mediaType = mediaType
  }
}

extension DownloadedFile: Identifiable {
  public var id: URL { fileURL }
}
