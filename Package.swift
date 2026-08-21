// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "jfc",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "jfc", targets: ["JFC"])
  ],
  targets: [
    .executableTarget(
      name: "JFC",
      path: "Sources/JFC"
    )
  ]
)
