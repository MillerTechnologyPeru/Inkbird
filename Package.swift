// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Inkbird",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "Inkbird",
            targets: ["Inkbird"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            .upToNextMajor(from: "6.0.0")
        ),
        .package(
            url: "https://github.com/PureSwift/GATT.git",
            .upToNextMajor(from: "3.0.0")
        ),
    ],
    targets: [
        .target(
            name: "Inkbird",
            dependencies: [
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "GATT",
                    package: "GATT"
                ),
            ]
        ),
        .testTarget(
            name: "InkbirdTests",
            dependencies: ["Inkbird"]
        )
    ]
)
