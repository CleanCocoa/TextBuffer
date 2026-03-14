// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TextBuffer",
    platforms: [.macOS(.v13)],
    products: [
      .library(
          name: "TextBuffer",
          targets: ["TextBuffer"]),
      .library(
          name: "TextBufferTesting",
          targets: ["TextBufferTesting"]),
    ],
    targets: [
        .target(name: "TextBuffer"),
        .target(
            name: "TextBufferTesting",
            dependencies: ["TextBuffer"]),
        .testTarget(
            name: "TextBufferTests",
            dependencies: ["TextBuffer", "TextBufferTesting"]),
    ]
)
