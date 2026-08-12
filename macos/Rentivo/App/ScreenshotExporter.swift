#if DEBUG

  import AppKit
  import SwiftUI

  /// Debug-only, launch-argument driven window self-capture.
  ///
  /// `--screenshot-export <directory>` (or `--screenshot-export=<directory>`) walks the app
  /// through its sections, writes one PNG per section into the directory, and quits. The pixels
  /// come from the app's own window through AppKit rather than from the `screencapture` tool,
  /// because that tool needs the screen-recording permission an unattended machine cannot grant.
  ///
  /// Combined with `--screenshot-authenticated` it exports every `AppTab`; on its own it exports
  /// a single `login.png` of the anonymous screen.
  ///
  /// The app is sandboxed, so it can only write inside its container. A directory it is not
  /// allowed to write to is mirrored into `NSTemporaryDirectory()`
  /// (`~/Library/Containers/<bundle id>/Data/tmp/<directory name>`), which the log names.
  @MainActor
  enum ScreenshotExporter {
    static let exportArgument = "--screenshot-export"
    static let authenticatedArgument = "--screenshot-authenticated"

    /// One PNG to produce. `tab` is `nil` when the shot captures whatever is already on screen.
    struct Shot: Equatable {
      let fileName: String
      let tab: AppTab?
    }

    struct Plan: Equatable {
      let directory: URL
      let shots: [Shot]
    }

    /// Settle time granted to the first layout before the first capture.
    private static let launchSettleDuration = Duration.milliseconds(600)
    /// Settle time granted to a section switch. The mock store answers immediately, but the
    /// staggered appear animations do not.
    private static let sectionSettleDuration = Duration.milliseconds(800)
    private static let windowPollInterval = Duration.milliseconds(100)
    private static let windowPollAttempts = 150
    /// Polls to wait before nudging AppKit into opening the window it decided to withhold.
    private static let untitledWindowNudgeAttempt = 10
    /// Smallest side, in points, a window must have to be the app window rather than a panel.
    private static let minimumWindowSide: CGFloat = 200

    /// Reads the plan out of the launch arguments, or returns `nil` when no export was requested.
    static func plan(arguments: [String]) -> Plan? {
      guard let path = directoryPath(in: arguments) else { return nil }
      let directory = URL(fileURLWithPath: path, isDirectory: true)
      guard arguments.contains(authenticatedArgument) else {
        return Plan(directory: directory, shots: [Shot(fileName: "login", tab: nil)])
      }
      return Plan(directory: directory, shots: AppTab.allCases.map { Shot(fileName: fileName(for: $0), tab: $0) })
    }

    /// Both `--screenshot-export <dir>` and `--screenshot-export=<dir>` are accepted. The joined
    /// form is worth preferring: a bare value token reads to AppKit as a file the app was asked
    /// to open, and an app launched to open a file gets no untitled window (see `waitForWindow`).
    private static func directoryPath(in arguments: [String]) -> String? {
      if let joined = arguments.first(where: { $0.hasPrefix("\(exportArgument)=") }) {
        let path = String(joined.dropFirst(exportArgument.count + 1))
        return path.isEmpty ? nil : path
      }
      guard let flagIndex = arguments.firstIndex(of: exportArgument) else { return nil }
      let pathIndex = arguments.index(after: flagIndex)
      guard arguments.indices.contains(pathIndex) else { return nil }
      let path = arguments[pathIndex]
      // Without this, a value-less flag would swallow the next flag as a directory name.
      guard !path.isEmpty, !path.hasPrefix("-") else { return nil }
      return path
    }

    /// Stable, English file stems — these name build artifacts, not user-facing copy.
    static func fileName(for tab: AppTab) -> String {
      switch tab {
      case .home: "home"
      case .billings: "billings"
      case .organizations: "organizations"
      case .account: "account"
      }
    }

    /// Whether an export was asked for, which also decides that the app must run on mock data.
    static func isRequested(arguments: [String]) -> Bool {
      plan(arguments: arguments) != nil
    }

    /// Arms the export, if the launch arguments ask for one. Called from `RentivoMacApp.init`,
    /// so the work starts as soon as the main run loop turns.
    static func installIfRequested(app: AppModel, arguments: [String]) {
      guard let plan = plan(arguments: arguments) else { return }
      Task { @MainActor in await run(plan: plan, app: app) }
    }

    static func run(plan: Plan, app: AppModel) async {
      defer { NSApp.terminate(nil) }
      guard let directory = writableDirectory(for: plan.directory) else { return }
      guard let window = await waitForWindow() else {
        log("no window to capture")
        return
      }
      // The window is drawn whether or not it is frontmost, but ordering it in keeps the capture
      // identical to what a person would see.
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      try? await Task.sleep(for: launchSettleDuration)

      for shot in plan.shots {
        if let tab = shot.tab { app.selectedTab = tab }
        try? await Task.sleep(for: sectionSettleDuration)
        let destination = directory.appendingPathComponent("\(shot.fileName).png")
        guard let data = pngData(of: window) else {
          log("captured nothing for \(shot.fileName)")
          continue
        }
        do {
          try data.write(to: destination)
          log("wrote \(destination.path) (\(data.count) bytes)")
        } catch {
          log("could not write \(destination.path): \(error.localizedDescription)")
        }
      }
    }

    /// The requested directory, or — when the sandbox refuses it — a same-named directory inside
    /// the container. Returns `nil` only when even the container is unusable.
    private static func writableDirectory(for requested: URL) -> URL? {
      if prepare(requested) { return requested }
      let fallback = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(requested.lastPathComponent, isDirectory: true)
      guard prepare(fallback) else {
        log("neither \(requested.path) nor \(fallback.path) is writable")
        return nil
      }
      log("the sandbox refuses \(requested.path); writing to \(fallback.path) instead")
      return fallback
    }

    /// Creates the directory and proves it accepts a file, which is the only reliable way to
    /// learn that the sandbox allows writing there.
    private static func prepare(_ directory: URL) -> Bool {
      let probe = directory.appendingPathComponent(".rentivo-screenshot-probe")
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: probe)
        try? FileManager.default.removeItem(at: probe)
        return true
      } catch {
        return false
      }
    }

    /// Polls until the window group has produced a laid-out window.
    private static func waitForWindow() async -> NSWindow? {
      for attempt in 0..<windowPollAttempts {
        if let window = capturableWindow() { return window }
        // An app that AppKit believes was launched to open a file gets no untitled window, and a
        // launch argument value looks exactly like such a file. Asking for the window directly
        // covers that case and is a no-op once the window already exists.
        if attempt == untitledWindowNudgeAttempt {
          _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
        }
        try? await Task.sleep(for: windowPollInterval)
      }
      return capturableWindow()
    }

    /// The document window, told apart from panels and menu windows by its size. It is not
    /// necessarily on screen yet, which is why visibility only breaks ties.
    private static func capturableWindow() -> NSWindow? {
      let candidates = NSApp.windows.filter { window in
        guard let view = window.contentView else { return false }
        return view.bounds.width >= minimumWindowSide && view.bounds.height >= minimumWindowSide
      }
      return candidates.first(where: \.isVisible) ?? candidates.first
    }

    /// Captures the window, title bar included. Reading back the window's own composited image is
    /// what SwiftUI's content survives: `cacheDisplay` walks the AppKit view tree and returns an
    /// empty content area, so it is only the fallback for when the window list yields nothing.
    /// Both paths capture this process's own window, so neither needs screen-recording
    /// permission — unlike the `screencapture` tool.
    static func pngData(of window: NSWindow) -> Data? {
      if let image = windowListImage(of: window) {
        let rep = NSBitmapImageRep(cgImage: image)
        if !isVisuallyBlank(rep), let data = rep.representation(using: .png, properties: [:]) {
          return data
        }
      }
      return cachedDisplayPNGData(of: window)
    }

    // Deprecated in macOS 14 in favour of ScreenCaptureKit, which needs the permission this whole
    // exporter exists to avoid. Marking the wrapper deprecated documents that and keeps the call
    // site quiet.
    @available(macOS, deprecated: 14.0)
    private static func windowListImage(of window: NSWindow) -> CGImage? {
      guard window.windowNumber > 0 else { return nil }
      return CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowNumber),
        [.boundsIgnoreFraming, .bestResolution])
    }

    private static func cachedDisplayPNGData(of window: NSWindow) -> Data? {
      guard let contentView = window.contentView else { return nil }
      let view = contentView.superview ?? contentView
      guard view.bounds.width > 1, view.bounds.height > 1,
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { return nil }
      view.cacheDisplay(in: view.bounds, to: rep)
      return rep.representation(using: .png, properties: [:])
    }

    /// True when every sampled pixel has the same colour, which is what an unrendered
    /// (all-white or all-transparent) capture looks like.
    static func isVisuallyBlank(_ rep: NSBitmapImageRep, samplesPerAxis: Int = 16) -> Bool {
      let width = rep.pixelsWide
      let height = rep.pixelsHigh
      guard width > 0, height > 0, samplesPerAxis > 1 else { return true }

      var reference: NSColor?
      for row in 0..<samplesPerAxis {
        for column in 0..<samplesPerAxis {
          let x = column * (width - 1) / (samplesPerAxis - 1)
          let y = row * (height - 1) / (samplesPerAxis - 1)
          guard let sample = rep.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB) else { continue }
          guard let known = reference else {
            reference = sample
            continue
          }
          if !matches(sample, known) { return false }
        }
      }
      return true
    }

    private static func matches(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
      let tolerance = 1.0 / 255.0
      return abs(lhs.redComponent - rhs.redComponent) <= tolerance
        && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
        && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
        && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
    }

    /// Progress goes to stderr, which is where a run started from a terminal can read it, and to
    /// the unified log for a run started through LaunchServices.
    private static func log(_ message: String) {
      NSLog("[screenshot-export] %@", message)
    }
  }

#endif
