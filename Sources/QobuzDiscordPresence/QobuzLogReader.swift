import Foundation

enum QobuzLogReader {
    static func currentTrack() async -> NowPlayingTrack? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readCurrentTrack())
            }
        }
    }

    private static func readCurrentTrack() -> NowPlayingTrack? {
        guard let trackID = latestPlayingTrackID(),
              let metadata = metadata(for: trackID) else {
            return nil
        }

        return NowPlayingTrack(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            elapsed: nil,
            playbackRate: 1,
            sourceApplication: "Qobuz",
            bundleIdentifier: "com.qobuz.desktop",
            artworkURL: metadata.artworkURL
        )
    }

    private static func latestPlayingTrackID() -> String? {
        guard let logURL = newestLogURL(),
              let log = try? String(contentsOf: logURL, encoding: .utf8) else {
            return nil
        }

        var latestTrackID: String?

        for line in log.split(separator: "\n").reversed() {
            if line.contains("Status has changed to Stopped") {
                return nil
            }

            if let trackID = trackID(from: String(line)) {
                latestTrackID = trackID
                break
            }
        }

        return latestTrackID
    }

    private static func newestLogURL() -> URL? {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qobuz/logs")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("rapport_qobuz") }
            .max { lhs, rhs in
                modificationDate(for: lhs) < modificationDate(for: rhs)
            }
    }

    private static func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func trackID(from line: String) -> String? {
        guard let range = line.range(of: "Play track ") else {
            return nil
        }

        let suffix = line[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func metadata(for trackID: String) -> TrackMetadata? {
        guard trackID.allSatisfy(\.isNumber) else {
            return nil
        }

        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qobuz/qobuz.db")

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return nil
        }

        let query = """
        select title, track_artists_names, release_name, duration, release_image_small
        from S_Track
        where id = \(trackID)
        limit 1;
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-separator", "\t", dbURL.path, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let row = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !row.isEmpty else {
            return nil
        }

        let columns = row.components(separatedBy: "\t")
        guard columns.count >= 5 else {
            return nil
        }

        return TrackMetadata(
            title: columns[0],
            artist: emptyToNil(columns[1]),
            album: emptyToNil(columns[2]),
            duration: TimeInterval(columns[3]),
            artworkURL: largerArtworkURL(from: emptyToNil(columns[4]))
        )
    }

    private static func emptyToNil(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func largerArtworkURL(from url: String?) -> String? {
        guard let url else {
            return nil
        }

        return url
            .replacingOccurrences(of: "_230.jpg", with: "_600.jpg")
            .replacingOccurrences(of: "_150.jpg", with: "_600.jpg")
    }

    private struct TrackMetadata {
        let title: String
        let artist: String?
        let album: String?
        let duration: TimeInterval?
        let artworkURL: String?
    }
}
