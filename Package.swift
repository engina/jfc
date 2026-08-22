// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "jfc",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "jfc", targets: ["JFC"]),
    .executable(name: "JFCApp", targets: ["JFCApp"]),
    .executable(name: "JFCLoginItem", targets: ["JFCLoginItem"]),
  ],
  targets: [
    .target(
      name: "JFCCore",
      path: "Sources/JFCCore"
    ),
    .executableTarget(
      name: "JFC",
      dependencies: ["JFCCore"],
      path: "Sources/JFC",
      sources: [
        "CLIOptions.swift",
        "JFCMain.swift",
      ]
    ),
    .executableTarget(
      name: "JFCApp",
      dependencies: ["JFCCore"],
      path: "Sources/JFCApp"
    ),
    .executableTarget(
      name: "JFCLoginItem",
      path: "Sources/JFCLoginItem"
    ),
  ]
)
