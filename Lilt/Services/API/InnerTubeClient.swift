import Foundation

enum InnerTubeError: LocalizedError {
    case notSignedIn
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to YouTube Music to search."
        case .http(let code): "YouTube Music returned an error (\(code))."
        case .badResponse: "Couldn't read the response from YouTube Music."
        }
    }
}

/// A parsed JSON object. JSONSerialization returns immutable Foundation values, so handing the
/// tree between tasks is safe even though `[String: Any]` can't be marked Sendable.
struct JSONObject: @unchecked Sendable {
    let value: [String: Any]
}

/// Minimal InnerTube transport: a JSON POST to `music.youtube.com/youtubei/v1/<endpoint>`
/// with browser-shaped headers, the shared WebKit cookies and a SAPISIDHASH signature.
@MainActor
final class InnerTubeClient {
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static let clientVersion = "1.20250929.01.00"

    private let auth: AuthService
    private let session: URLSession

    init(auth: AuthService) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    func post(_ endpoint: String, body: [String: Any]) async throws -> JSONObject {
        let cookies = await auth.youtubeCookies()
        guard let sapisid = InnerTubeAuth.sapisid(in: cookies) else {
            throw InnerTubeError.notSignedIn
        }

        var payload = body
        payload["context"] = Self.context()
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(InnerTubeAuth.origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(InnerTubeAuth.origin, forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeAuth.origin, forHTTPHeaderField: "X-Origin")
        request.setValue("\(InnerTubeAuth.origin)/", forHTTPHeaderField: "Referer")
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        request.setValue(InnerTubeAuth.cookieHeader(cookies), forHTTPHeaderField: "Cookie")
        request.setValue(InnerTubeAuth.sapisidHash(sapisid: sapisid), forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            auth.sessionExpired()
            throw InnerTubeError.http(status)
        }
        guard (200..<300).contains(status) else { throw InnerTubeError.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw InnerTubeError.badResponse
        }
        return JSONObject(value: json)
    }

    private static func context() -> [String: Any] {
        let locale = Locale.current
        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": clientVersion,
                "hl": locale.language.languageCode?.identifier ?? "en",
                "gl": locale.region?.identifier ?? "US",
                "platform": "DESKTOP",
            ],
            "user": ["lockedSafetyMode": false],
        ]
    }
}
