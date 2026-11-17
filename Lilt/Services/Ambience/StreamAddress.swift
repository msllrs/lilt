import Foundation

/// The address a pasted feed actually plays from. A listener usually copies what the site puts
/// in front of them — a player page or a playlist — rather than the mount itself, and LiveATC's
/// page links are behind a bot check and their `.pls` is a text file AVPlayer can't read. The
/// mount behind both is the same stream, so it is what Lilt asks for.
enum StreamAddress {
    /// The stream to play, or nil if what was pasted isn't one: not an HTTP address, or a
    /// LiveATC page that names no mount.
    static func stream(from pasted: String) -> URL? {
        guard var parts = URLComponents(string: pasted.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host?.lowercased()
        else { return nil }

        guard host == "liveatc.net" || host.hasSuffix(".liveatc.net") else { return parts.url }
        guard let mount = mount(in: parts) else { return nil }

        parts.scheme = "https"
        parts.host = "d.liveatc.net"
        parts.port = nil
        parts.user = nil
        parts.password = nil
        parts.path = "/" + mount
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    /// The mount a LiveATC address names: `/play/<mount>.pls`, `hlisten.php?mount=<mount>`, or
    /// the mount itself on the stream host. Nil for a page that names none, such as a search.
    private static func mount(in parts: URLComponents) -> String? {
        if parts.path.hasPrefix("/play/") {
            return clean(String(parts.path.dropFirst("/play/".count)))
        }
        if parts.path == "/hlisten.php" {
            return clean(parts.queryItems?.first { $0.name == "mount" }?.value ?? "")
        }
        if parts.host?.lowercased() == "d.liveatc.net" {
            return clean(String(parts.path.dropFirst()))
        }
        return nil
    }

    /// A mount name, with a playlist's extension taken off; nil if it holds anything a mount
    /// wouldn't, so no page is played as one.
    private static func clean(_ name: String) -> String? {
        var name = name
        for suffix in [".pls", ".m3u"] where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return name
    }
}
