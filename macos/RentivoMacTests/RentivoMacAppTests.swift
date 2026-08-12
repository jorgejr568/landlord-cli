import Testing

@testable import Rentivo

@Suite("macOS app target")
struct RentivoMacAppTests {
  @Test("the placeholder window is titled Rentivo")
  func placeholderTitle() {
    #expect(PlaceholderContent.title == "Rentivo")
  }

  /// The separator BRL currency formatting emits is a non-breaking space, spelled out here so the
  /// expectation stays readable.
  @Test("the placeholder balance is formatted as BRL by RentivoCore")
  func placeholderFormatsMoneyThroughCore() {
    #expect(PlaceholderContent.zeroBalance == "R$\u{00A0}0,00")
  }
}
