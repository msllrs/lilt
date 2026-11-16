import Foundation
import MetricKit

/// Crash and hang reports, which macOS hands to MetricKit on the launch after they happen, kept
/// in the diagnostics folder as JSON beside the log. An Objective-C exception that would end the
/// app is written to the log as it happens, with its stack.
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    private let diagnostics: Diagnostics

    init(diagnostics: Diagnostics = .shared) {
        self.diagnostics = diagnostics
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
        // Reports delivered while Lilt wasn't listening (it's only told of new ones otherwise).
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.shared.record(.app, "uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))")
            Diagnostics.shared.flush()
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let kinds = [
                (payload.crashDiagnostics?.isEmpty == false, "crash"),
                (payload.hangDiagnostics?.isEmpty == false, "hang"),
                (payload.cpuExceptionDiagnostics?.isEmpty == false, "cpu"),
                (payload.diskWriteExceptionDiagnostics?.isEmpty == false, "disk-writes"),
            ].filter(\.0).map(\.1)
            diagnostics.recordReport(payload.jsonRepresentation(), kind: kinds.joined(separator: "+").nilIfEmpty ?? "diagnostic")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
