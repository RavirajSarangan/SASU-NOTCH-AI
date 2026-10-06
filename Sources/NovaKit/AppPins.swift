import Foundation

/// Which apps the notch dock shows by default: the ones the user has
/// installed, from a list of common daily apps.
public enum AppPins {
    public static let candidates = [
        "com.microsoft.VSCode", "com.google.Chrome", "com.brave.Browser", "net.whatsapp.WhatsApp",
        "com.spotify.client", "com.microsoft.Word", "com.apple.Safari",
    ]

    public static func defaults(isInstalled: (String) -> Bool, limit: Int = 6) -> [String] {
        Array(candidates.filter(isInstalled).prefix(limit))
    }
}
