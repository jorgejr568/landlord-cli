import AppKit
import SwiftUI

extension Date {
  /// Formats this date pinned to the pt-BR locale, so PT-BR sentences never leak a
  /// device-locale date string (e.g. "Jul 23, 2026" showing up on an en-US device
  /// inside otherwise-Portuguese copy).
  func formattedPTBR(
    date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
    time timeStyle: Date.FormatStyle.TimeStyle = .omitted
  ) -> String {
    formatted(Date.FormatStyle(date: dateStyle, time: timeStyle, locale: Locale(identifier: "pt_BR")))
  }
}

extension Color {
  /// Parses one of the API's theme colors, with or without a leading `#`. Returns `nil` for any
  /// value that isn't six hexadecimal digits, so a half-typed field falls back to a default
  /// instead of rendering an arbitrary color.
  init?(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }

  /// The inverse of `init?(hex:)`, used to write a `ColorPicker` selection back into the API's
  /// hex string. Returns `nil` for colors that have no sRGB representation.
  var hexString: String? {
    guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
    let red = Int((components.redComponent * 255).rounded())
    let green = Int((components.greenComponent * 255).rounded())
    let blue = Int((components.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}
