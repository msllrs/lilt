import Foundation
import os

/// Lilt's own record of what happened, kept on this Mac so a bug can be traced after the fact:
/// one line per event in `Diagnostics/lilt.log` (rolled over to `lilt.1.log` before it grows
/// large), crash and hang reports from MetricKit beside it, and, only while Settings ▸
/// Diagnostics asks for it, the raw YouTube Music responses a parser fix can be tested against.
/// Nothing leaves the Mac. Each line also goes to the unified log, readable with
/// `log stream --predicate 'subsystem == "com.msllrs.Lilt"'`.
///
/// Writes happen on a queue of their own, so recording from the main actor costs nothing.
final class Diagnostics: @unchecked Sendable {
    enum Category: String {
        case app, network, player, notice, screen
    }

    /// The test host is a whole Lilt sharing the app's container; its lines go to a folder of
    /// their own so they never read as something the app did.
    static let shared = Diagnostics(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? "Diagnostics" : "Diagnostics (Tests)")
    )

    /// Whether raw responses are kept. Off by default: they hold the library's contents.
    static let recordsResponsesKey = "recordsResponses"

    let directory: URL
    var logURL: URL { directory.appendingPathComponent("lilt.log") }
    var responsesURL: URL { directory.appendingPathComponent("Responses") }

    private let defaults: UserDefaults
    private let limit: Int
    private let responseLimit: Int
    private let queue = DispatchQueue(label: "com.msllrs.Lilt.diagnostics")
    private var handle: FileHandle?
    private var size = 0
    private var responseCount = 0
    private static let logger = Logger(subsystem: "com.msllrs.Lilt", category: "diagnostics")

    init(directory: URL, defaults: UserDefaults = .standard, limit: Int = 1_000_000, responseLimit: Int = 300) {
        self.directory = directory
        self.defaults = defaults
        self.limit = limit
        self.responseLimit = responseLimit
    }

    var recordsResponses: Bool { defaults.bool(forKey: Self.recordsResponsesKey) }

    func record(_ category: Category, _ message: String) {
        Self.logger.notice("\(category.rawValue, privacy: .public) \(message, privacy: .public)")
        let line = "\(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))) \(category.rawValue) \(message)\n"
        queue.async { self.append(Data(line.utf8)) }
    }

    /// Keeps `data`, the response to `endpoint` called with `body`, as a file named for what
    /// was asked (`browse-FEmusic_home`, `next-<videoId>`), with the request beside it.
    func recordResponse(_ data: Data, endpoint: String, body: [String: Any]) {
        guard recordsResponses else { return }
        var request = body
        request["context"] = nil
        let asked = (request["browseId"] ?? request["videoId"] ?? request["playlistId"]) as? String
            ?? (request["continuation"] != nil ? "continuation" : request["query"] != nil ? "query" : "request")
        let stamp = Date.now.formatted(Self.stamp)
        let name = "\(endpoint)-\(asked.prefix(60))"
        let wrapped: Data? = {
            guard let response = try? JSONSerialization.jsonObject(with: data),
                  JSONSerialization.isValidJSONObject(request) else { return nil }
            return try? JSONSerialization.data(withJSONObject: ["request": request, "response": response], options: [.sortedKeys])
        }()
        guard let wrapped else { return }
        queue.async { self.write(wrapped, stamp: stamp, named: name) }
    }

    /// The kept responses, oldest first.
    func recordedResponses() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: responsesURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Keeps a crash or hang report MetricKit delivered.
    func recordReport(_ data: Data, kind: String) {
        let name = "\(kind)-\(Date.now.formatted(Self.stamp)).json"
        queue.async {
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try? data.write(to: self.directory.appendingPathComponent(name), options: .atomic)
        }
        record(.app, "\(kind) report saved as \(name)")
    }

    /// Waits for every write so far; for tests, and before showing the folder.
    func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    // MARK: Writing (on `queue`)

    private static let stamp = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
        timeZone: .current, calendar: .current
    )

    private func append(_ data: Data) {
        if handle == nil { open() }
        if size + data.count > limit { rollOver() }
        handle?.write(data)
        size += data.count
    }

    private func open() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: logURL)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rollOver() {
        try? handle?.close()
        handle = nil
        let older = directory.appendingPathComponent("lilt.1.log")
        try? FileManager.default.removeItem(at: older)
        try? FileManager.default.moveItem(at: logURL, to: older)
        open()
    }

    private func write(_ data: Data, stamp: String, named name: String) {
        try? FileManager.default.createDirectory(at: responsesURL, withIntermediateDirectories: true)
        // A counter keeps names in the order written when several land in the same second.
        responseCount += 1
        let file = responsesURL.appendingPathComponent("\(stamp)-\(String(format: "%05d", responseCount % 100_000))-\(name).json")
        try? data.write(to: file, options: .atomic)
        let kept = recordedResponses()
        for old in kept.dropLast(responseLimit) { try? FileManager.default.removeItem(at: old) }
    }
}
