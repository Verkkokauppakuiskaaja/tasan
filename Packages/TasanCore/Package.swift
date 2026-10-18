// swift-tools-version:5.9
import PackageDescription

/*
 * TasanCore holds the family model and all rules that do not
 * need Apple frameworks: the Finnish year clock, responsibility
 * transfers, load summary and the family meeting agenda.
 * Keeping it Foundation-only lets the rules be tested with
 * `swift test` on any machine, including Linux CI.
 */
let package = Package(
  name: "TasanCore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "TasanCore", targets: ["TasanCore"])
  ],
  targets: [
    .target(name: "TasanCore"),
    .testTarget(name: "TasanCoreTests", dependencies: ["TasanCore"]),
  ]
)
