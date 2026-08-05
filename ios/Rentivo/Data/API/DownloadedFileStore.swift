import Foundation

/// Owns the on-disk lifecycle of the files `LiveAPIClient.download(path:filename:)` produces.
///
/// Downloads land in a dedicated subdirectory of `tmp/` rather than in `tmp/` itself, so the app
/// can remove exactly its own downloads without touching scratch files URLSession and other
/// frameworks write there. Outside the `Data` layer only `remove(_:)` is needed.
public struct DownloadedFileStore: Sendable {
  /// The store every production `LiveAPIClient` uses. Tests inject their own directory instead, so
  /// that a purge in one test cannot delete a file another test is still reading — Swift Testing
  /// runs `@Test` functions concurrently.
  public static let shared = DownloadedFileStore()

  /// `.completeFileProtectionUnlessOpen` keeps the bytes encrypted at rest while the device is
  /// locked and the file is not already open, instead of inheriting the container default.
  /// `.atomic` is preserved from the original write so a partial file is never observable as a
  /// complete one.
  public static let writingOptions: Data.WritingOptions = [
    .atomic, .completeFileProtectionUnlessOpen,
  ]

  public let directory: URL

  public init(
    directory: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("RentivoDownloads", isDirectory: true)
  ) {
    self.directory = directory
  }

  /// Creates the downloads directory if needed and returns a collision-free destination carrying
  /// `pathExtension`, which is what lets `ShareLink` and the receiving app infer the file's type.
  func makeDestination(pathExtension: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(pathExtension)
  }

  /// Removes one downloaded file. Best effort: a file iOS already reclaimed from `tmp/` on its own
  /// schedule is not a failure worth surfacing to the caller.
  public static func remove(_ file: DownloadedFile) {
    try? FileManager.default.removeItem(at: file.fileURL)
  }

  /// Removes every file this store produced, so nothing an authenticated session downloaded
  /// outlives that session.
  public func purge() {
    try? FileManager.default.removeItem(at: directory)
  }
}
