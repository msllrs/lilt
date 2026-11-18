import AppKit
import UserNotifications

/// Settings ▸ Notifications: a notification with the title, the artist and the cover each time
/// the song changes. There is only ever one: each replaces the last under the same identifier,
/// so Notification Centre holds what's playing rather than a history.
@MainActor
final class SongNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "notifyOnSongChange"
    private static let identifier = "nowPlaying"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private let player: PlayerService
    /// The panel, to tell the listener's own clicks from everything else.
    private let panel: () -> NSWindow?
    /// The song last seen, so a restored one at launch or a repeat of the same song is no change.
    private var lastId: String?

    init(player: PlayerService, panel: @escaping () -> NSWindow?) {
        self.player = player
        self.panel = panel
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        lastId = player.current?.id
        observe()
    }

    /// Asked only when the setting is turned on. False when the user said no, now or before.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    /// The user has turned Lilt's notifications off in System Settings.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private func observe() {
        withObservationTracking {
            _ = player.current?.id
        } onChange: { [weak self] in
            guard let self else { return }
            // Called as the song changes, inside whatever caused it, so a click that did it is
            // still the current event here (it won't be once the task below runs).
            let own = MainActor.assumeIsolated {
                let panel = self.panel()
                return Self.isOwnAction(NSApp.currentEvent, in: panel, panelInFront: panel.map(Self.isInFront) ?? false)
            }
            Task { @MainActor [weak self] in
                self?.songChanged(byOwnAction: own)
                self?.observe()
            }
        }
    }

    /// The rule: a change is the listener's own when it came from a click or key press in the
    /// panel while the panel is visible and key. They're looking at it, so a banner would only
    /// repeat what they just did. Everything else posts: a song ending, media keys and the
    /// Dock menu, which reach Lilt without an event in the panel.
    static func isOwnAction(_ event: NSEvent?, in panel: NSWindow?, panelInFront: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let event, let panel, panelInFront, event.window === panel else { return false }
        // `currentEvent` is the last event dispatched, not necessarily one being handled now: a
        // click minutes before a song ends by itself mustn't count.
        return now - event.timestamp < 1
    }

    /// Hidden, Lilt's panel is parked at zero alpha rather than ordered out.
    private static func isInFront(_ panel: NSWindow) -> Bool {
        panel.isVisible && panel.isKeyWindow && panel.alphaValue > 0
    }

    private func songChanged(byOwnAction own: Bool) {
        guard let track = player.current, track.id != lastId else { return }
        lastId = track.id
        guard Self.isEnabled, !own else { return }
        Task { await post(track) }
    }

    private func post(_ track: Track) async {
        var attachments: [UNNotificationAttachment] = []
        if let url = track.artworkURL, let image = await ImageCache.shared.load(url), let cover = Self.attachment(image) {
            attachments = [cover]
        }
        // The song may have moved on while the cover loaded.
        guard Self.isEnabled, player.current?.id == track.id else { return }
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = track.artist
        content.attachments = attachments
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// The cover as a file: an attachment is read from disk, and the notification store moves
    /// the file in, so each one gets a copy of its own in the temporary folder.
    private static func attachment(_ image: NSImage) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString).png")
        do {
            try png.write(to: file)
            return try UNNotificationAttachment(identifier: "cover", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown even while Lilt is the active app: the panel being up isn't the same as looking
    /// at it, and the rule above already leaves out the changes made there.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Clicking the notification brings the panel up.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppDelegate.shared?.showPanel() }
    }
}
