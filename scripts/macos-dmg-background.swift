// Renders the drag-to-Applications background image for the installer disk image.
//
// Invoked by `scripts/macos-dmg.sh`; not meant to be run directly. The image is the DMG window's
// backdrop: Finder draws the Rentivo.app and Applications icons on top of it at the coordinates the
// packaging script sets, so the two icon wells drawn here must line up with those coordinates. The
// bitmap is rendered at 2x and tagged 144dpi so Finder treats it as a `width` x `height` point
// backdrop that stays sharp on Retina displays.
//
// Everything is drawn with CoreGraphics and CoreText only — no network access, no external tooling.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Window content size in points. The packaging script uses the same numbers.
let width: CGFloat = 540
let height: CGFloat = 380
let scale: CGFloat = 2

// Icon well centres, in points from the top-left of the window (Finder's coordinate space).
// The packaging script positions the app and the Applications alias at exactly these points.
let appCenter = CGPoint(x: 145, y: 190)
let applicationsCenter = CGPoint(x: 395, y: 190)
let iconSide: CGFloat = 128

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("macos-dmg-background: \(message)\n".utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
  fail("usage: macos-dmg-background.swift <app-icon.png> <output.png>")
}
let iconURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[1])

guard let iconSource = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
  let iconImage = CGImageSourceCreateImageAtIndex(iconSource, 0, nil)
else {
  fail("cannot read the app icon at \(iconURL.path)")
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
  fail("cannot create the sRGB color space")
}

/// Builds an sRGB color from 8-bit channels, which keeps the palette readable as hex-style values.
func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> CGColor {
  let components: [CGFloat] = [
    CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, alpha,
  ]
  guard let color = CGColor(colorSpace: colorSpace, components: components) else {
    fail("cannot create an sRGB color")
  }
  return color
}

// Palette: the Rentivo blue-grey family, light enough that Finder's icon labels stay legible.
let backdropTop = rgba(246, 248, 252)
let backdropBottom = rgba(223, 231, 242)
let accent = rgba(45, 90, 150)
let folderFill = rgba(196, 214, 238)
let folderStroke = rgba(120, 152, 196)
let headline = rgba(30, 52, 82)

guard
  let context = CGContext(
    data: nil,
    width: Int(width * scale),
    height: Int(height * scale),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )
else {
  fail("cannot create the background bitmap context")
}
context.interpolationQuality = .high
context.scaleBy(x: scale, y: scale)

/// Converts a top-left origin point to the bottom-left origin CoreGraphics uses.
func flipped(_ point: CGPoint) -> CGPoint {
  CGPoint(x: point.x, y: height - point.y)
}

/// The square Finder will draw an icon into, centred on a top-left origin point.
func iconRect(centeredAt center: CGPoint) -> CGRect {
  let origin = flipped(center)
  return CGRect(
    x: origin.x - iconSide / 2,
    y: origin.y - iconSide / 2,
    width: iconSide,
    height: iconSide
  )
}

guard
  let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [backdropTop, backdropBottom] as CFArray,
    locations: [0, 1]
  )
else {
  fail("cannot create the backdrop gradient")
}
context.drawLinearGradient(
  gradient,
  start: CGPoint(x: 0, y: height),
  end: CGPoint(x: 0, y: 0),
  options: []
)

// The app icon, ghosted where Finder will place Rentivo.app. Finder paints the real icon on top at
// the same spot, so what remains visible is a halo that survives the user changing the icon size.
context.saveGState()
context.setAlpha(0.35)
context.draw(iconImage, in: iconRect(centeredAt: appCenter))
context.restoreGState()

/// A rounded folder silhouette standing in for /Applications. The outline is a single closed path
/// — a body with a tab on its top left — so the two parts share one fill and one stroke and no
/// seam shows where they meet.
func drawFolder(in rect: CGRect) {
  let body = rect.insetBy(dx: 8, dy: 20)
  let tabHeight: CGFloat = 16
  let shoulder = body.maxY - tabHeight
  let tabRight = body.minX + body.width * 0.44
  let corners = [
    CGPoint(x: body.minX, y: body.minY),
    CGPoint(x: body.minX, y: body.maxY),
    CGPoint(x: tabRight, y: body.maxY),
    CGPoint(x: tabRight, y: shoulder),
    CGPoint(x: body.maxX, y: shoulder),
    CGPoint(x: body.maxX, y: body.minY),
  ]
  let path = CGMutablePath()
  // Rounded polygon: start on an edge midpoint so every corner gets a tangent arc.
  path.move(to: CGPoint(x: (corners[5].x + corners[0].x) / 2, y: body.minY))
  for index in corners.indices {
    path.addArc(
      tangent1End: corners[index],
      tangent2End: corners[(index + 1) % corners.count],
      radius: 8
    )
  }
  path.closeSubpath()
  context.saveGState()
  context.addPath(path)
  context.setFillColor(folderFill)
  context.fillPath()
  context.addPath(path)
  context.setStrokeColor(folderStroke)
  context.setLineWidth(1.5)
  context.strokePath()
  context.restoreGState()
}
drawFolder(in: iconRect(centeredAt: applicationsCenter))

/// The horizontal arrow pointing from the app at the Applications folder.
func drawArrow(from start: CGPoint, to end: CGPoint) {
  let headLength: CGFloat = 22
  let headHalfWidth: CGFloat = 11
  let shaftEnd = CGPoint(x: end.x - headLength, y: end.y)
  context.saveGState()
  context.setStrokeColor(accent)
  context.setLineWidth(6)
  context.setLineCap(.round)
  context.move(to: start)
  context.addLine(to: shaftEnd)
  context.strokePath()

  let head = CGMutablePath()
  head.move(to: end)
  head.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y + headHalfWidth))
  head.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y - headHalfWidth))
  head.closeSubpath()
  context.addPath(head)
  context.setFillColor(accent)
  context.fillPath()
  context.restoreGState()
}
let arrowY = flipped(appCenter).y
drawArrow(
  from: CGPoint(x: appCenter.x + iconSide / 2 + 14, y: arrowY),
  to: CGPoint(x: applicationsCenter.x - iconSide / 2 - 14, y: arrowY)
)

/// Draws a horizontally centred line of text, positioned by its distance from the window top.
func drawCenteredText(_ string: String, size: CGFloat, topY: CGFloat, color: CGColor) {
  let font =
    CTFontCreateUIFontForLanguage(.system, size, nil)
    ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
  // The `.font`/`.foregroundColor` shorthands come from AppKit; this script links CoreText only,
  // so the CoreText attribute names are used directly.
  let attributed = NSAttributedString(
    string: string,
    attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
  )
  let line = CTLineCreateWithAttributedString(attributed)
  let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
  context.saveGState()
  context.textPosition = CGPoint(x: (width - bounds.width) / 2, y: height - topY)
  CTLineDraw(line, context)
  context.restoreGState()
}
// Customer-facing copy is PT-BR.
drawCenteredText("Arraste o Rentivo para Aplicativos", size: 19, topY: 306, color: headline)

guard let image = context.makeImage() else {
  fail("cannot rasterize the background image")
}
guard
  let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  )
else {
  fail("cannot open \(outputURL.path) for writing")
}
let properties: [CFString: Any] = [
  kCGImagePropertyDPIWidth: 72 * scale,
  kCGImagePropertyDPIHeight: 72 * scale,
]
CGImageDestinationAddImage(destination, image, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
  fail("cannot write \(outputURL.path)")
}
