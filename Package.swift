// swift-tools-version:5.9
import PackageDescription

// DesktopKit comes from GitHub. To build against a local checkout while changing
// the framework, set DESKTOPKIT_PATH, e.g. `DESKTOPKIT_PATH=../desktop-framework ./build.sh`.
let desktopKit: Package.Dependency = {
    if let path = Context.environment["DESKTOPKIT_PATH"], !path.isEmpty {
        return .package(name: "desktop-widgets", path: path)
    }
    return .package(url: "https://github.com/rob901/desktop-widgets.git", branch: "main")
}()

let package = Package(
    name: "DesktopNotes",
    platforms: [.macOS(.v14)],
    dependencies: [desktopKit],
    targets: [
        .executableTarget(
            name: "DesktopNotes",
            dependencies: [.product(name: "DesktopKit", package: "desktop-widgets")]
        ),
    ]
)
