import AppKit
import Foundation

enum DiscordClientDetector {
    private static let bundleIdentifiers = [
        "com.hnc.Discord",
        "com.hnc.DiscordCanary",
        "com.hnc.DiscordPTB"
    ]

    private static let appNames = [
        "Discord",
        "Discord Canary",
        "Discord PTB"
    ]

    static func runningClientName() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = app.bundleIdentifier else {
                continue
            }

            if bundleIdentifiers.contains(bundleIdentifier) {
                return app.localizedName ?? displayName(for: bundleIdentifier)
            }
        }

        return nil
    }

    static func openBestAvailableClient() {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }

        for name in appNames {
            let url = URL(fileURLWithPath: "/Applications").appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }
    }

    private static func displayName(for bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.hnc.DiscordCanary":
            return "Discord Canary"
        case "com.hnc.DiscordPTB":
            return "Discord PTB"
        default:
            return "Discord"
        }
    }
}
