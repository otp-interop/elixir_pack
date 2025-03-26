// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "<#PACKAGE_NAME#>",
    platforms: [.iOS(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "<#PACKAGE_NAME#>",
            targets: ["<#PACKAGE_NAME#>"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "<#PACKAGE_NAME#>",
            dependencies: ["liberlang"],
            resources: [.copy("_elixirkit_build")]
        ),
        .binaryTarget(
            name: "liberlang",
            path: "liberlang.xcframework"
        ),

        .testTarget(name: "<#PACKAGE_NAME#>Tests", dependencies: ["<#PACKAGE_NAME#>"])
    ]
)
