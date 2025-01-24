// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TextBuffer",
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
