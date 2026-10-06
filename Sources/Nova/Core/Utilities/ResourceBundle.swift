import AppKit

/// Finds files in the SwiftPM resource bundle. Looks inside the .app's
/// Resources first (where build_app.sh puts it) before falling back to
/// `Bundle.module`, which only resolves next to the binary or in .build.
@MainActor
enum ResourceBundle {
    private static let bundleName = "Nova_Nova.bundle"

    private static let bundles: [Bundle] = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        .compactMap { $0?.appendingPathComponent(bundleName) }
        .compactMap(Bundle.init(url:))

    private static var imageCache: [String: NSImage] = [:]

    static func url(_ name: String, ext: String, subdirectory: String? = nil) -> URL? {
        for bundle in bundles {
            if let url = find(name, ext, subdirectory, in: bundle) { return url }
        }
        // Evaluated last: `Bundle.module` traps if the bundle can't be found.
        return find(name, ext, subdirectory, in: .module)
    }

    static func image(_ name: String, ext: String, subdirectory: String? = nil, template: Bool = false) -> NSImage? {
        let key = "\(subdirectory ?? "")/\(name).\(ext)"
        if let cached = imageCache[key] { return cached }
        guard let url = url(name, ext: ext, subdirectory: subdirectory),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = template
        imageCache[key] = image
        return image
    }

    private static func find(_ name: String, _ ext: String, _ subdirectory: String?, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? subdirectory.flatMap { bundle.url(forResource: name, withExtension: ext, subdirectory: $0) }
    }
}
