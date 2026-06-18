import AppKit
import Foundation
import Combine

@MainActor
final class PresenceCoordinator: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                refreshNow()
            } else {
                Task { await clearPresence() }
            }
        }
    }

    @Published private(set) var statusText = "Starting..."
    @Published private(set) var currentTrack: NowPlayingTrack?
    @Published private(set) var isPublishing = false
    @Published private(set) var discordClientName = "Detecting..."

    private var timer: Timer?
    private var discord = DiscordIPC()
    private var lastPublishedTrackID: String?
    private var lastOpenAttempt: Date?

    private let bundledQobuzDiscordApplicationID = "1247655024637513778"

    private var clientID: String {
        bundledQobuzDiscordApplicationID
    }

    private var pollInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "pollInterval")
        return value > 0 ? value : 5
    }

    private var onlyQobuz: Bool {
        if UserDefaults.standard.object(forKey: "onlyQobuz") == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: "onlyQobuz")
    }

    func start() {
        if UserDefaults.standard.object(forKey: "pollInterval") == nil {
            UserDefaults.standard.set(5.0, forKey: "pollInterval")
        }
        if UserDefaults.standard.object(forKey: "onlyQobuz") == nil {
            UserDefaults.standard.set(false, forKey: "onlyQobuz")
        }
        UserDefaults.standard.removeObject(forKey: "discordClientID")

        reloadSettings()
    }

    func reloadSettings() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        refreshNow()
    }

    func refreshNow() {
        guard isEnabled else {
            return
        }

        updateDiscordClientStatus()

        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            statusText = "Missing built-in Qobuz Discord Application ID."
            isPublishing = false
            return
        }

        Task {
            var track = await NowPlayingReader.currentTrack()
            if track == nil {
                track = await QobuzLogReader.currentTrack()
            }

            await MainActor.run {
                self.currentTrack = track
            }

            guard let track else {
                await clearPresence(status: "No current media found.")
                return
            }

            if onlyQobuz && !track.isFromQobuz {
                await clearPresence(status: "Ignoring \(track.sourceApplication ?? "another media app").")
                return
            }

            do {
                try await discord.publish(track: track, clientID: trimmedClientID)
                await MainActor.run {
                    self.lastPublishedTrackID = track.stableID
                    self.isPublishing = true
                    self.updateDiscordClientStatus()
                    self.statusText = "Publishing to \(self.discordClientName)."
                }
            } catch {
                await MainActor.run {
                    if case DiscordIPCError.discordNotFound = error {
                        self.openDiscordIfNeeded()
                    }
                    self.isPublishing = false
                    self.statusText = error.localizedDescription
                }
            }
        }
    }

    func openDiscord() {
        DiscordClientDetector.openBestAvailableClient()
        updateDiscordClientStatus()
    }

    private func clearPresence(status: String = "Presence cleared.") async {
        do {
            if !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await discord.clear(clientID: clientID)
            }
        } catch {
            await MainActor.run {
                self.statusText = error.localizedDescription
            }
            return
        }

        await MainActor.run {
            self.lastPublishedTrackID = nil
            self.isPublishing = false
            self.statusText = status
        }
    }

    private func updateDiscordClientStatus() {
        if let client = DiscordClientDetector.runningClientName() {
            discordClientName = client
        } else {
            discordClientName = "Not running"
        }
    }

    private func openDiscordIfNeeded() {
        let now = Date()
        if let lastOpenAttempt, now.timeIntervalSince(lastOpenAttempt) < 30 {
            return
        }

        lastOpenAttempt = now
        DiscordClientDetector.openBestAvailableClient()
        updateDiscordClientStatus()
    }
}
