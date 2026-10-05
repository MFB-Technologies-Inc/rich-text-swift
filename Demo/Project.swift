// Project.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import ProjectDescription

/// Manual-testing app for the package in the parent directory. The package is
/// referenced by path, so edits under ../Sources show up on the next build with
/// no regeneration.
let project = Project(
    name: "SwiftRichTextDemo",
    packages: [
        .local(path: ".."),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
    ]),
    targets: [
        .target(
            name: "SwiftRichTextDemo",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.mfbtech.SwiftRichTextDemo",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "RichText Demo",
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SwiftRichText"),
            ]
        ),
    ]
)
