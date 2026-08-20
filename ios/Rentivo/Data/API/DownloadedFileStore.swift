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
  public static let writingOptions: Data.WritingOptions = {
    #if os(iOS)
      return [.atomic, .completeFileProtectionUnlessOpen]
    #else
      // Darwin exposes iOS file-protection flags to macOS, but a command-line/package process can
      // create a file it is then forbidden to reopen. macOS relies on its app-container and normal
      // filesystem protection; the iOS app retains the stronger locked-device class above.
      return [.atomic]
    #endif
  }()

  public let directory: URL

  public init(
    directory: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("RentivoDownloads", isDirectory: true)
  ) {
    self.directory = directory
  }

  /// Creates a private per-download directory so collisions cannot change the human final name.
  func makeDestination(filename: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let downloadDirectory = directory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: downloadDirectory, withIntermediateDirectories: false)
    return downloadDirectory.appendingPathComponent(
      DocumentPresentation.sanitizedFilename(filename), isDirectory: false)
  }

  /// Removes one downloaded file. Best effort: a file iOS already reclaimed from `tmp/` on its own
  /// schedule is not a failure worth surfacing to the caller.
  public func remove(_ file: DownloadedFile) {
    removeDestination(file.fileURL)
  }

  /// Removes a destination created by `makeDestination`, including an incomplete write or move.
  /// Refusing URLs outside this store's root keeps cleanup from trusting a caller-provided UUID
  /// directory name by itself.
  func removeDestination(_ fileURL: URL) {
    let root = directory.standardizedFileURL
    let downloadDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
    guard
      downloadDirectory.deletingLastPathComponent().standardizedFileURL == root,
      UUID(uuidString: downloadDirectory.lastPathComponent) != nil
    else { return }
    try? FileManager.default.removeItem(at: downloadDirectory)
  }

  /// Removes every file this store produced, so nothing an authenticated session downloaded
  /// outlives that session.
  public func purge() {
    try? FileManager.default.removeItem(at: directory)
  }
}
