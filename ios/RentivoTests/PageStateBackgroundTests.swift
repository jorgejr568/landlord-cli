import SwiftUI
import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  /// The screens compose `PageStateView` with a `.background(RentivoColors.paper)`. A branch that
  /// only takes its intrinsic height leaves the rest of the screen showing the system background,
  /// which reads as a white page with a cream band across the middle.
  @MainActor
  private func renderedCorners(
    of state: LoadState<[Int]>
  ) throws -> (topLeading: RGB, bottomLeading: RGB) {
    let view =
      PageStateView(
        state: state,
        emptyState: EmptyStateConfiguration(
          title: "Nenhuma cobrança ainda",
          message: "Crie sua primeira cobrança para começar a gerar faturas.",
          systemImage: "doc.text"
        )
      ) { _ in
        EmptyView()
      } retry: {
      }
      .background(RentivoColors.paper)
      .frame(width: 320, height: 640)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    return (try RGB(image, x: 4, y: 4), try RGB(image, x: 4, y: 636))
  }

  private struct RGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    init(_ image: CGImage, x: Int, y: Int) throws {
      var pixel: [UInt8] = [0, 0, 0, 0]
      let context = try #require(
        CGContext(
          data: &pixel,
          width: 1,
          height: 1,
          bitsPerComponent: 8,
          bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
      context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
      red = Int(pixel[0])
      green = Int(pixel[1])
      blue = Int(pixel[2])
    }

    /// Rendering rounds the token's floating-point components, so compare with a small tolerance.
    func matches(_ color: Color) -> Bool {
      let components = UIColor(color).cgColor.components ?? []
      guard components.count >= 3 else { return false }
      let expected = components.prefix(3).map { Int(($0 * 255).rounded()) }
      return zip([red, green, blue], expected).allSatisfy { abs($0 - $1) <= 2 }
    }
  }

  @MainActor
  @Test func emptyStateFillsItsContainerSoTheScreenBackgroundPaintsEdgeToEdge() throws {
    let corners = try renderedCorners(of: .empty)
    #expect(corners.topLeading.matches(RentivoColors.paper))
    #expect(corners.bottomLeading.matches(RentivoColors.paper))
  }

  @MainActor
  @Test func failureStateFillsItsContainerSoTheScreenBackgroundPaintsEdgeToEdge() throws {
    let corners = try renderedCorners(of: .failed(DemoError(message: "Falha de rede")))
    #expect(corners.topLeading.matches(RentivoColors.paper))
    #expect(corners.bottomLeading.matches(RentivoColors.paper))
  }

  @MainActor
  @Test func loadingStateFillsItsContainerSoTheScreenBackgroundPaintsEdgeToEdge() throws {
    let corners = try renderedCorners(of: .loading)
    #expect(corners.topLeading.matches(RentivoColors.paper))
    #expect(corners.bottomLeading.matches(RentivoColors.paper))
  }
#endif
