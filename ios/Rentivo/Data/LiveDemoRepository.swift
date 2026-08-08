import Foundation

// The live app has no demo switches to flip, so this satisfies `DemoRepository` for
// `AppDependencies.live` while every demo setting stays at its inert default.
@MainActor
public final class LiveDemoRepository: DemoRepository {
  public private(set) var demoSettings = DemoSettings.standard
  public init() {}
  public func failNextOperation() {}
  public func setEmptyMode(_ enabled: Bool) { demoSettings.emptyMode = enabled }
  public func setViewerMode(_ enabled: Bool) { demoSettings.viewerMode = enabled }
  public func setDelayEnabled(_ enabled: Bool) { demoSettings.delayEnabled = enabled }
  public func reset() { demoSettings = .standard }
}
