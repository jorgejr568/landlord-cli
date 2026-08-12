#if DEBUG

  import AppKit
  import Foundation
  import Testing

  @testable import Rentivo

  @Suite("screenshot export launch arguments")
  @MainActor
  struct ScreenshotExporterPlanTests {
    @Test("no plan without the export flag")
    func absentFlagProducesNoPlan() {
      #expect(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-authenticated"]) == nil)
    }

    @Test("a flag without a usable directory produces no plan")
    func missingDirectoryProducesNoPlan() {
      #expect(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-export"]) == nil)
      #expect(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-export", ""]) == nil)
      #expect(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-export", "--ui-testing"]) == nil)
    }

    @Test("the joined form carries the directory too")
    func joinedFormIsAccepted() throws {
      let plan = try #require(
        ScreenshotExporter.plan(
          arguments: ["Rentivo", "--screenshot-authenticated", "--screenshot-export=/tmp/shots"]))
      #expect(plan.directory.path == "/tmp/shots")
      #expect(plan.shots.count == AppTab.allCases.count)
      #expect(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-export="]) == nil)
    }

    @Test("the anonymous export is a single login shot")
    func anonymousExportCapturesTheLoginScreen() throws {
      let plan = try #require(ScreenshotExporter.plan(arguments: ["Rentivo", "--screenshot-export", "/tmp/shots"]))
      #expect(plan.directory.path == "/tmp/shots")
      #expect(plan.shots == [ScreenshotExporter.Shot(fileName: "login", tab: nil)])
    }

    @Test("the authenticated export walks every section in sidebar order")
    func authenticatedExportCoversEverySection() throws {
      let plan = try #require(
        ScreenshotExporter.plan(
          arguments: ["Rentivo", "--screenshot-authenticated", "--screenshot-export", "/tmp/shots"]))
      #expect(plan.shots.map(\.tab) == AppTab.allCases.map { $0 })
      #expect(plan.shots.map(\.fileName) == ["home", "billings", "organizations", "account"])
    }

    @Test("an export request is what forces mock data")
    func requestDetectionMatchesThePlan() {
      #expect(ScreenshotExporter.isRequested(arguments: ["Rentivo", "--screenshot-export", "/tmp/shots"]))
      #expect(ScreenshotExporter.isRequested(arguments: ["Rentivo", "--screenshot-export=/tmp/shots"]))
      #expect(!ScreenshotExporter.isRequested(arguments: ["Rentivo", "--ui-testing"]))
    }

    @Test("every section maps to its own file stem")
    func fileNamesAreUnique() {
      let names = AppTab.allCases.map(ScreenshotExporter.fileName(for:))
      #expect(Set(names).count == AppTab.allCases.count)
    }
  }

  @Suite("blank capture detection")
  @MainActor
  struct ScreenshotExporterBlankDetectionTests {
    private func makeBitmap(draw: (NSRect) -> Void) -> NSBitmapImageRep {
      let size = NSSize(width: 64, height: 64)
      let image = NSImage(size: size)
      image.lockFocusFlipped(false)
      draw(NSRect(origin: .zero, size: size))
      image.unlockFocus()
      let data = image.tiffRepresentation!
      return NSBitmapImageRep(data: data)!
    }

    @Test("a uniform capture counts as blank")
    func uniformCaptureIsBlank() {
      let rep = makeBitmap { bounds in
        NSColor.white.setFill()
        bounds.fill()
      }
      #expect(ScreenshotExporter.isVisuallyBlank(rep))
    }

    @Test("a capture with drawn content is not blank")
    func drawnCaptureIsNotBlank() {
      let rep = makeBitmap { bounds in
        NSColor.white.setFill()
        bounds.fill()
        NSColor.black.setFill()
        bounds.insetBy(dx: 8, dy: 8).fill()
      }
      #expect(!ScreenshotExporter.isVisuallyBlank(rep))
    }

    @Test("a degenerate sample grid is treated as blank")
    func degenerateGridIsBlank() {
      let rep = makeBitmap { bounds in
        NSColor.black.setFill()
        bounds.fill()
      }
      #expect(ScreenshotExporter.isVisuallyBlank(rep, samplesPerAxis: 1))
    }
  }

#endif
