// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MidokuSources",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MidokuSources", targets: ["MidokuSourcesPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0"),
        .package(url: "https://github.com/Aidoku/AidokuRunner", branch: "main"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "MidokuSourcesPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "AidokuRunner", package: "AidokuRunner"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "ios/Sources/MidokuSourcesPlugin"
        )
    ]
)
