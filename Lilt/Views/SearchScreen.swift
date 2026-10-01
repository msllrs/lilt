import SwiftUI

struct SearchScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded([Track])
        case failed(String)
    }

    @State private var query = ""
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query)
                .padding(.top, Theme.Size.titlebarInset)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)
            content
        }
        .task(id: query) { await search() }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isSignedIn {
            SignedOutView()
        } else {
            switch phase {
            case .idle:
                EmptyHint(symbol: "magnifyingglass", title: "Search YouTube Music", detail: "Songs you find here play in the panel.")
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyHint(symbol: "exclamationmark.triangle", title: "Something went wrong", detail: message)
            case .loaded(let tracks) where tracks.isEmpty:
                EmptyHint(symbol: "music.note", title: "No songs found", detail: "Try a different search.")
            case .loaded(let tracks):
                TrackList(tracks: tracks)
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        if case .idle = phase { phase = .loading }
        do {
            let tracks = try await music.searchSongs(trimmed)
            guard !Task.isCancelled else { return }
            phase = .loaded(tracks)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct SignedOutView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            EmptyHint(symbol: "person.crop.circle", title: "Sign in to YouTube Music", detail: "Lilt uses your account and Premium subscription.")
            Button("Sign In") { auth.isPresentingLogin = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
