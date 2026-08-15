import AppKit
import SwiftUI

enum AppLaunchOptions {
  static let defaultWindowSize = CGSize(width: 1280, height: 800)

  static func initialWindowSize(arguments: [String]) -> CGSize {
    uiTestWindowSize(arguments: arguments) ?? defaultWindowSize
  }

  static func uiTestWindowSize(arguments: [String]) -> CGSize? {
    let prefix = "--ui-test-window-width="
    guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
      let width = Int(argument.dropFirst(prefix.count)),
      width == 760 || width == 1280
    else {
      return nil
    }
    return CGSize(width: CGFloat(width), height: defaultWindowSize.height)
  }
}

#if DEBUG
  struct UITestWindowSizeOverride: NSViewRepresentable {
    let size: CGSize?

    func makeNSView(context: Context) -> WindowSizeView {
      WindowSizeView(size: size)
    }

    func updateNSView(_ view: WindowSizeView, context: Context) {
      view.size = size
      view.applySizeIfNeeded()
    }
  }

  final class WindowSizeView: NSView {
    var size: CGSize?

    init(size: CGSize?) {
      self.size = size
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      applySizeIfNeeded()
    }

    override func layout() {
      super.layout()
      // `WindowGroup.defaultSize` can be restored after `viewDidMoveToWindow`. Reassert the
      // deterministic UI-test size on the following AppKit layout pass; the equality guard in
      // `applySizeIfNeeded` makes the settled window a no-op.
      applySizeIfNeeded()
    }

    func applySizeIfNeeded() {
      guard let size, let window, window.contentLayoutRect.size != size else { return }
      window.setContentSize(size)
    }
  }
#endif
