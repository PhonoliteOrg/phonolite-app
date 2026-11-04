// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_secure_storage_macos", platforms: [.macOS("10.14")],
  products: [.library(name: "flutter-secure-storage-macos", targets: ["flutter_secure_storage_macos"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .target(
      name: "flutter_secure_storage_macos",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
      resources: [.process("Resources/PrivacyInfo.xcprivacy")])
  ])
