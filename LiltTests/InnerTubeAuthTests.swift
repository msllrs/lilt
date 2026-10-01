import Foundation
import Testing
@testable import Lilt

struct InnerTubeAuthTests {
    @Test func sapisidHashMatchesKnownVector() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let header = InnerTubeAuth.sapisidHash(sapisid: "test-sapisid", date: date)
        #expect(header == "SAPISIDHASH 1700000000_17d748c166afd876ceb872a291e5befdca771528")
    }

    @Test func prefersSAPISIDOverThirdPartyCookie() {
        let cookies = [
            cookie(name: "__Secure-3PAPISID", value: "third"),
            cookie(name: "SAPISID", value: "first"),
        ]
        #expect(InnerTubeAuth.sapisid(in: cookies) == "first")
        #expect(InnerTubeAuth.sapisid(in: [cookies[0]]) == "third")
        #expect(InnerTubeAuth.sapisid(in: []) == nil)
    }

    @Test func cookieHeaderJoinsPairs() {
        let header = InnerTubeAuth.cookieHeader([cookie(name: "a", value: "1"), cookie(name: "b", value: "2")])
        #expect(header == "a=1; b=2")
    }

    private func cookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: ".youtube.com", .path: "/"])!
    }
}
