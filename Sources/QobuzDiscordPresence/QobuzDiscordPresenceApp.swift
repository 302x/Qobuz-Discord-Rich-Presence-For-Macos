import SwiftUI

@main
struct QobuzDiscordPresenceApp: App {
    @StateObject private var coordinator = PresenceCoordinator()

    var body: some Scene {
        MenuBarExtra {
            AppMenuView(coordinator: coordinator)
                .frame(width: 340)
        } label: {
            Image(systemName: coordinator.isPublishing ? "music.note.tv.fill" : "music.note.tv")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AppMenuView: View {
    @ObservedObject var coordinator: PresenceCoordinator
    @AppStorage("pollInterval") private var pollInterval = 5.0
    @AppStorage("onlyQobuz") private var onlyQobuz = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qobuz Discord")
                        .font(.headline)
                    Text(coordinator.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Toggle("", isOn: $coordinator.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            HStack {
                Text("Local Discord")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(coordinator.discordClientName)
                    .lineLimit(1)
            }
            .font(.caption)

            Text("Using the built-in Qobuz Discord activity profile.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Only publish when Qobuz is the media app", isOn: $onlyQobuz)
                .onChange(of: onlyQobuz) { _ in
                    coordinator.reloadSettings()
                }

            HStack {
                Text("Refresh")
                    .foregroundStyle(.secondary)
                Slider(value: $pollInterval, in: 2...20, step: 1)
                    .onChange(of: pollInterval) { _ in
                        coordinator.reloadSettings()
                    }
                Text("\(Int(pollInterval))s")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            .font(.caption)

            if let track = coordinator.currentTrack {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " - "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(track.sourceApplication ?? "Now Playing")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                Button("Refresh Now") {
                    coordinator.refreshNow()
                }

                Button("Open Discord") {
                    coordinator.openDiscord()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .onAppear {
            coordinator.start()
        }
    }
}
