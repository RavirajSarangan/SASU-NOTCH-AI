import AppKit

@MainActor
enum MascotAssets {
    static let body = load("nova_body")
    static let head = load("nova_head")

    static func pose(_ pose: NovaPose) -> NSImage {
        ResourceBundle.image(pose.resourceName, ext: "png", subdirectory: "Poses") ?? body
    }

    private static func load(_ name: String) -> NSImage {
        if let image = ResourceBundle.image(name, ext: "png", subdirectory: "Mascot") { return image }
        assertionFailure("Missing mascot art: \(name).png")
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
