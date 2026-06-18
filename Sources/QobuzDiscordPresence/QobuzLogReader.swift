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
        guard let playback = latestPlayback(),
              let metadata = metadata(for: playback.trackID) else {
            return nil
        }

        let elapsed = elapsedTime(since: playback.startedAt, duration: metadata.duration)

        return NowPlayingTrack(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            elapsed: elapsed,
            playbackRate: 1,
            sourceApplication: "Qobuz",
            bundleIdentifier: "com.qobuz.desktop",
            artworkURL: metadata.artworkURL
        )
    }

    private static func latestPlayback() -> Playback? {
        guard let logURL = newestLogURL(),
              let log = try? String(contentsOf: logURL, encoding: .utf8) else {
            return nil
        }

        for line in log.split(separator: "\n").reversed() {
            if line.contains("Status has changed to Stopped") {
                return nil
            }

            if let playback = playback(from: String(line)) {
                return playback
            }
        }

        return nil
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

    private static func playback(from line: String) -> Playback? {
        guard let range = line.range(of: "Play track ") else {
            return nil
        }

        let suffix = line[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty,
              let timestamp = timestamp(from: line) else {
            return nil
        }

        return Playback(trackID: String(digits), startedAt: timestamp)
    }

    private static func timestamp(from line: String) -> Date? {
        guard let end = line.range(of: "Z:")?.lowerBound else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(line[...end]))
    }

    private static func elapsedTime(since startedAt: Date, duration: TimeInterval?) -> TimeInterval {
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        guard let duration, duration > 0 else {
            return elapsed
        }

        return min(elapsed, duration)
    }

    private static func metadata(for trackID: String) -> TrackMetadata? {
        guard trackID.allSatisfy(\.isNumber) else {
            return nil
        }

        if let metadata = liveMetadata(for: trackID) {
            return metadata
        }

        return cachedMetadata(for: trackID)
    }

    private static func liveMetadata(for trackID: String) -> TrackMetadata? {
        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qobuz/qobuz.db")

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return nil
        }

        let query = """
        select
            json_extract(data, '$.title'),
            coalesce(
                json_extract(data, '$.performer.name'),
                json_extract(data, '$.album.artist.name')
            ),
            json_extract(data, '$.album.title'),
            json_extract(data, '$.duration'),
            coalesce(
                json_extract(data, '$.album.assetsAPI.large'),
                json_extract(data, '$.album.image.large'),
                json_extract(data, '$.album.image.thumbnail')
            )
        from L_Track
        where track_id = '\(trackID)'
        limit 1;
        """

        return trackMetadata(dbURL: dbURL, query: query)
    }

    private static func cachedMetadata(for trackID: String) -> TrackMetadata? {
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

        return trackMetadata(dbURL: dbURL, query: query)
    }

    private static func trackMetadata(dbURL: URL, query: String) -> TrackMetadata? {
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

    private struct Playback {
        let trackID: String
        let startedAt: Date
    }

    private struct TrackMetadata {
        let title: String
        let artist: String?
        let album: String?
        let duration: TimeInterval?
        let artworkURL: String?
    }
}
