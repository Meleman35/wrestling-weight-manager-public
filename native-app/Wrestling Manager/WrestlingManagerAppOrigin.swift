import Foundation

// Native privileges belong only to these app documents. Keep all bridges on
// one policy when migrating domains; never trust a suffix or arbitrary HTTPS.
enum WrestlingManagerAppOrigin {
    static func contains(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return false }

        switch url.host?.lowercased() {
        case "theteammanager.app":
            // The custom-domain app is a single-page document at the root.
            // Queries and fragments are allowed; www redirects to this host.
            return ["", "/", "/index.html"].contains(url.path)
        case "meleman35.github.io":
            let root = "/wrestling-weight-manager-public"
            let path = url.path
            guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
            return path == root || path.hasPrefix(root + "/")
        default:
            return false
        }
    }
}
