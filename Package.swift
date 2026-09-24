// swift-tools-version:5.9
//
//  Package.swift
//  VPNGuard
//
//  Standalone test harness for the pure logic that lives in `Shared/`.
//
//  The app itself is an Xcode target; running unit tests hosted in the app is
//  undesirable because AppDelegate registers the privileged helper on launch.
//  This package compiles only the dependency-free `Shared/` sources so tests can
//  run with `swift test` without launching the app.
//

import PackageDescription

let package = Package(
    name: "VPNGuardCore",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "VPNGuardCore",
            path: "Shared"
        ),
        .testTarget(
            name: "VPNGuardCoreTests",
            dependencies: ["VPNGuardCore"],
            path: "Tests/VPNGuardCoreTests"
        )
    ]
)
