// swift-tools-version: 6.0
// Deliberately 6.0 rather than the newest available: the tools version is a
// floor on every consumer's toolchain, and nothing here needs a later one.
import PackageDescription

/// swift-docc-plugin generates the documentation site. It is gated behind an
/// environment variable rather than declared unconditionally, for two reasons:
///
///   1. Zero dependencies stays literally true for consumers. The plugin is
///      build-time only and never links into a binary, but an unconditional
///      entry still shows up in every consumer's resolved graph.
///   2. It keeps `xcodebuild` usable in restricted environments. Any package
///      dependency forces xcodebuild to reach the network during resolution;
///      where that is blocked, an unconditional entry breaks the whole iOS
///      test loop, not merely the docs.
///
/// Generate docs with:  SWIFTRICHTEXT_DOCS=1 swift package generate-documentation --target RichTextCore
let docsDependencies: [Package.Dependency] =
    Context.environment["SWIFTRICHTEXT_DOCS"] == nil
        ? []
        : [.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")]

let benchmarkDependencies: [Package.Dependency] =
    Context.environment["SWIFTRICHTEXT_BENCHMARK"] == nil
        ? []
        : [.package(url: "https://github.com/ordo-one/benchmark", from: "1.36.2")]

let package = Package(
    name: "rich-text-swift",
    platforms: [
        .iOS(.v17),
        // Local-only: lets the platform-agnostic core build & run tests on the dev Mac.
        // NOT a macOS product commitment; a macOS port is future work. Pinned to
        // v14 (not v13) because RichTextEditorUI's view model uses Observation,
        // which the Observation framework requires.
        .macOS(.v14),
    ],
    products: [
        // Umbrella: re-exports the public layers for simple adoption. Grows as layers land.
        .library(name: "SwiftRichText", targets: ["SwiftRichText"]),
        // Headless core: server-side HTML conversion, tests, etc.
        .library(name: "RichTextCore", targets: ["RichTextCore"]),
    ],
    dependencies: docsDependencies + benchmarkDependencies,
    targets: [
        .target(name: "RichTextCore"),
        .target(name: "RichTextEngine", dependencies: ["RichTextCore"]),
        .target(name: "RichTextEditorUI", dependencies: ["RichTextCore", "RichTextEngine"]),
        .target(name: "SwiftRichText", dependencies: ["RichTextCore", "RichTextEngine", "RichTextEditorUI"]),
        .testTarget(name: "RichTextCoreTests", dependencies: ["RichTextCore"]),
        .testTarget(name: "RichTextEngineTests", dependencies: ["RichTextEngine"]),
        .testTarget(name: "RichTextEditorUITests", dependencies: ["RichTextEditorUI", "RichTextEngine"]),
    ],
    swiftLanguageModes: [.v6]
)

if Context.environment["SWIFTRICHTEXT_BENCHMARK"] != nil {
    // Benchmark of parsing-benchmarks
    package.targets += [
        .executableTarget(
            name: "RichTextCore-benchmarks",
            dependencies: [
                "RichTextCore",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/RichTextCore-benchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
            ]
        ),
    ]
}
