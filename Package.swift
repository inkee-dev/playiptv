// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlayIPTV",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PlayIPTV", targets: ["PlayIPTV"])
    ],
    dependencies: [
        .package(url: "https://github.com/tylerjonesio/vlckit-spm", from: "3.6.0")
    ],
    targets: [
        .executableTarget(
            name: "PlayIPTV",
            dependencies: [
                .product(name: "VLCKitSPM", package: "vlckit-spm")
            ],
            path: "Sources/PlayIPTV",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Sources/PlayIPTV/Info.plist"
                ])
            ]
        )
    ]
)
