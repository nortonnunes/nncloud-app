// swift-tools-version:5.9
// O cliente do NN Cloud sob demanda, em Swift: usado pela extensão File Provider
// (os mesmos arquivos entram no alvo NNCloudFP) e testado sozinho com `swift test`.
import PackageDescription

let package = Package(
    name: "NNCloudKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NNCloudKit", targets: ["NNCloudKit"])],
    targets: [
        .target(name: "NNCloudKit"),
        .testTarget(name: "NNCloudKitTests", dependencies: ["NNCloudKit"]),
    ]
)
