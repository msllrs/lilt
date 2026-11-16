import Foundation
import Testing
@testable import Lilt

/// Lilt's own record of what happened, kept on this Mac to trace a bug after the fact: a line
/// per event in a log that rolls over before it grows large, and, only while asked for, the
/// raw YouTube Music responses a parser fix can be tested against.
struct DiagnosticsTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticsTests-\(UUID().uuidString)")
    }

    @Test func aRecordedLineLandsInTheLog() throws {
        let dir = Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Diagnostics(directory: dir, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        log.record(.network, "browse FEmusic_home 200 312ms")
        log.record(.player, "playback error for abc: player onError 150")
        log.flush()
        let text = try String(contentsOf: log.logURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("network browse FEmusic_home 200 312ms"))
        #expect(lines[1].contains("player playback error for abc"))
    }

    @Test func theLogRollsOverPastItsLimit() throws {
        let dir = Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Diagnostics(directory: dir, defaults: UserDefaults(suiteName: UUID().uuidString)!, limit: 1_000)
        for i in 0..<100 { log.record(.app, "line \(i) " + String(repeating: "x", count: 40)) }
        log.flush()
        let size = try FileManager.default.attributesOfItem(atPath: log.logURL.path)[.size] as? Int ?? 0
        #expect(size <= 1_000, "the current log stays under its limit")
        let older = dir.appendingPathComponent("lilt.1.log")
        #expect(FileManager.default.fileExists(atPath: older.path), "the lines before it are kept in one older file")
        let all = try String(contentsOf: log.logURL, encoding: .utf8)
        #expect(all.contains("line 99 "), "the newest line is in the current log")
    }

    @Test func responsesAreRecordedOnlyWhenAskedFor() throws {
        let dir = Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let log = Diagnostics(directory: dir, defaults: defaults)
        let response = Data(#"{"contents":{}}"#.utf8)
        log.recordResponse(response, endpoint: "browse", body: ["browseId": "FEmusic_liked_playlists"])
        log.flush()
        #expect(log.recordedResponses().isEmpty, "off by default: library contents stay out of files")

        defaults.set(true, forKey: Diagnostics.recordsResponsesKey)
        log.recordResponse(response, endpoint: "browse", body: ["browseId": "FEmusic_liked_playlists"])
        log.flush()
        let files = log.recordedResponses()
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent.contains("browse-FEmusic_liked_playlists") == true)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: try #require(files.first))) as? [String: Any]
        #expect((saved?["request"] as? [String: Any])?["browseId"] as? String == "FEmusic_liked_playlists", "the request it answered is kept with it")
        #expect(saved?["response"] is [String: Any])
    }

    @Test func onlyTheNewestResponsesAreKept() throws {
        let dir = Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: Diagnostics.recordsResponsesKey)
        let log = Diagnostics(directory: dir, defaults: defaults, responseLimit: 5)
        for i in 0..<12 { log.recordResponse(Data("{}".utf8), endpoint: "next", body: ["videoId": "v\(i)"]) }
        log.flush()
        let names = log.recordedResponses().map(\.lastPathComponent)
        #expect(names.count == 5)
        #expect(names.contains { $0.hasSuffix("-v11.json") }, "the newest stays")
        #expect(!names.contains { $0.hasSuffix("-v0.json") }, "the oldest goes")
    }
}
