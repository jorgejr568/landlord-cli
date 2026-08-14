// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "RentivoCore",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "RentivoCore", targets: ["RentivoCore"])
  ],
  targets: [
    // `Rentivo/openapi.json` is the committed copy of the server contract, kept byte-identical to
    // `frontend/openapi.json` by `make ios-openapi-check`. For this package it is a reference
    // document, not a build input: the Data layer hand-writes its wire DTOs (see `RemoteDTOs.swift`),
    // so nothing in this package consumes generated code and no generator plugin runs here.
    // (The Xcode app target still carries the generator plugin — tracked as a follow-up.)
    .target(
      name: "RentivoCore",
      path: "Rentivo",
      exclude: [
        "App", "DesignSystem", "Features", "Resources",
        // App-target build inputs, not package sources: the Xcode app signs itself with the
        // entitlements file and reads the contract copy through its generator plugin.
        "Rentivo.entitlements", "openapi.json", "openapi-generator-config.yaml",
      ],
      sources: ["Domain", "Data"]
    ),
    .testTarget(
      name: "RentivoCoreTests",
      dependencies: ["RentivoCore"],
      path: "RentivoTests"
    ),
  ]
)
