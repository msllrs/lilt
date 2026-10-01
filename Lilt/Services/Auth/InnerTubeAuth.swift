import CryptoKit
import Foundation

/// Pure helpers for InnerTube cookie auth. No actor isolation so they can be unit tested
/// and called from network code.
enum InnerTubeAuth {
    static let origin = "https://music.youtube.com"

    /// Builds the `Authorization` header YouTube's web clients send:
    /// `SAPISIDHASH <unix seconds>_<sha1("<seconds> <SAPISID> <origin>")>`.
    static func sapisidHash(sapisid: String, origin: String = origin, date: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(seconds) \(sapisid) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(seconds)_\(hex)"
    }

    static func cookieHeader(_ cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func sapisid(in cookies: [HTTPCookie]) -> String? {
        if let c = cookies.first(where: { $0.name == "SAPISID" }) { return c.value }
        return cookies.first(where: { $0.name == "__Secure-3PAPISID" })?.value
    }

    static func isYouTubeCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.hasSuffix("youtube.com")
    }
}
