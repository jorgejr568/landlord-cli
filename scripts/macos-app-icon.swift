// Renders the macOS app-icon PNG set from a single square source image.
//
// Invoked by `scripts/macos-app-icon.sh`; not meant to be run directly. The source artwork is the
// iOS 1024x1024 icon, which fills its whole canvas. macOS icons instead sit on a 1024x1024 canvas
// with transparent margins: the artwork occupies a centred 824x824 rounded rect (corner radius
// 185.4pt), which is the Apple macOS icon grid. Every emitted size is downsampled from that single
// master so the set stays visually consistent, and ImageIO writes deterministic PNGs so repeated
// runs leave the asset catalog byte-identical.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasSide = 1024.0
let artworkSide = 824.0
let cornerRadius = 185.4

/// Emitted files, as (pixel side, file name). Points 16/32/128/256/512 at @1x and @2x.
let outputs: [(pixels: Int, name: String)] = [
  (16, "AppIcon-16.png"),
  (32, "AppIcon-16@2x.png"),
  (32, "AppIcon-32.png"),
  (64, "AppIcon-32@2x.png"),
  (128, "AppIcon-128.png"),
  (256, "AppIcon-128@2x.png"),
  (256, "AppIcon-256.png"),
  (512, "AppIcon-256@2x.png"),
  (512, "AppIcon-512.png"),
  (1024, "AppIcon-512@2x.png"),
]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("macos-app-icon: \(message)\n".utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
  fail("usage: macos-app-icon.swift <source.png> <output-directory>")
}
let sourceURL = URL(fileURLWithPath: arguments[0])
let outputDirectory = URL(fileURLWithPath: arguments[1])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
  let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fail("cannot read source image at \(sourceURL.path)")
}
guard sourceImage.width == sourceImage.height else {
  fail("source image must be square, got \(sourceImage.width)x\(sourceImage.height)")
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
  fail("cannot create the sRGB color space")
}

func makeContext(side: Int) -> CGContext {
  guard
    let context = CGContext(
      data: nil,
      width: side,
      height: side,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    fail("cannot create a \(side)x\(side) bitmap context")
  }
  context.interpolationQuality = .high
  return context
}

// Master: the artwork clipped to the rounded rect, centred on a transparent 1024x1024 canvas.
let masterContext = makeContext(side: Int(canvasSide))
let inset = (canvasSide - artworkSide) / 2
let artworkRect = CGRect(x: inset, y: inset, width: artworkSide, height: artworkSide)
masterContext.addPath(
  CGPath(
    roundedRect: artworkRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
  )
)
masterContext.clip()
masterContext.draw(sourceImage, in: artworkRect)
guard let masterImage = masterContext.makeImage() else {
  fail("cannot rasterize the master icon")
}

for output in outputs {
  let context = makeContext(side: output.pixels)
  let side = Double(output.pixels)
  context.draw(masterImage, in: CGRect(x: 0, y: 0, width: side, height: side))
  guard let image = context.makeImage() else {
    fail("cannot rasterize \(output.name)")
  }
  let destinationURL = outputDirectory.appendingPathComponent(output.name)
  guard
    let destination = CGImageDestinationCreateWithURL(
      destinationURL as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    fail("cannot open \(destinationURL.path) for writing")
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fail("cannot write \(destinationURL.path)")
  }
}
