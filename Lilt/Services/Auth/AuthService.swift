import Foundation
import Observation
import WebKit

/// Owns the shared WebKit data store. Signed-in state is derived from the presence of a
/// SAPISID cookie for youtube.com; the login sheet and the hidden player share this store.
@MainActor
@Observable
final class AuthService {
    private(set) var isSignedIn = false
    var isPresentingLogin = false

    let dataStore: WKWebsiteDataStore = .default()

    func refresh() async {
        let cookies = await youtubeCookies()
        isSignedIn = InnerTubeAuth.sapisid(in: cookies) != nil
    }

    func youtubeCookies() async -> [HTTPCookie] {
        let all = await dataStore.httpCookieStore.allCookies()
        return all.filter(InnerTubeAuth.isYouTubeCookie)
    }

    /// Called by the API client on 401/403.
    func sessionExpired() {
        isSignedIn = false
        isPresentingLogin = true
    }

    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let google = records.filter {
            $0.displayName.contains("youtube") || $0.displayName.contains("google")
        }
        await dataStore.removeData(ofTypes: types, for: google)
        isSignedIn = false
    }
}
