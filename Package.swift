// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MidokuCollectionCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MidokuCollectionCore", targets: ["MidokuCollectionCore"])],
    targets: [
        .target(name: "MidokuCollectionCore", path: "Midoku/Core/Collection",
            exclude: ["CollectionStore.swift", "CollectionReader.swift", "CollectionAdoption.swift"],
            sources: ["CollectionModels.swift", "CollectionIntegrity.swift", "CollectionTypes.swift", "CollectionHierarchy.swift", "CollectionBookmarks.swift"]),
        .testTarget(name: "MidokuCollectionCoreTests", dependencies: ["MidokuCollectionCore"], path: "Tests/Collection")
    ]
)
