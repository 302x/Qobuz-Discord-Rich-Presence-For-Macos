import Foundation

struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsed: TimeInterval?
    let playbackRate: Double?
    let sourceApplication: String?
    let bundleIdentifier: String?
    let artworkURL: String?

    var isFromQobuz: Bool {
        let source = [sourceApplication, bundleIdentifier]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return source.contains("qobuz")
    }

    var isPlaying: Bool {
        (playbackRate ?? 1) > 0
    }

    var stableID: String {
        [title, artist, album, sourceApplication, artworkURL].compactMap { $0 }.joined(separator: "|")
    }
}

enum NowPlayingReader {
    private typealias InfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void

    static func currentTrack() async -> NowPlayingTrack? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: readCurrentTrack())
            }
        }
    }

    private static func readCurrentTrack() -> NowPlayingTrack? {
        guard let mediaRemote = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            return nil
        }

        defer {
            dlclose(mediaRemote)
        }

        guard let symbol = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo") else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: InfoFunction.self)
        let semaphore = DispatchSemaphore(value: 0)
        var info: [String: Any]?

        function(DispatchQueue.global(qos: .userInitiated)) { dictionary in
            if let dictionary {
                info = dictionary as NSDictionary as? [String: Any]
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2)

        guard let info, let title = firstString(info, keys: [
            "kMRMediaRemoteNowPlayingInfoTitle",
            "title"
        ]), !title.isEmpty else {
            return nil
        }

        let clientProperties = clientProperties(from: info)

        return NowPlayingTrack(
            title: title,
            artist: firstString(info, keys: [
                "kMRMediaRemoteNowPlayingInfoArtist",
                "artist"
            ]),
            album: firstString(info, keys: [
                "kMRMediaRemoteNowPlayingInfoAlbum",
                "album"
            ]),
            duration: firstDouble(info, keys: [
                "kMRMediaRemoteNowPlayingInfoDuration",
                "duration"
            ]),
            elapsed: firstDouble(info, keys: [
                "kMRMediaRemoteNowPlayingInfoElapsedTime",
                "elapsedTime"
            ]),
            playbackRate: firstDouble(info, keys: [
                "kMRMediaRemoteNowPlayingInfoPlaybackRate",
                "playbackRate"
            ]),
            sourceApplication: firstString(clientProperties, keys: [
                "displayName",
                "applicationDisplayName",
                "name"
            ]) ?? firstString(info, keys: [
                "kMRMediaRemoteNowPlayingInfoApplicationDisplayName",
                "applicationDisplayName"
            ]),
            bundleIdentifier: firstString(clientProperties, keys: [
                "bundleIdentifier",
                "bundleID",
                "applicationBundleIdentifier"
            ]) ?? firstString(info, keys: [
                "kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier",
                "applicationBundleIdentifier"
            ]),
            artworkURL: nil
        )
    }

    private static func firstString(_ info: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = info[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstDouble(_ info: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = info[key] as? Double {
                return value
            }
            if let value = info[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    private static func clientProperties(from info: [String: Any]) -> [String: Any] {
        let keys = [
            "kMRMediaRemoteNowPlayingInfoClientPropertiesData",
            "clientPropertiesData"
        ]

        for key in keys {
            guard let data = info[key] as? Data else {
                continue
            }

            if let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ), let dictionary = plist as? [String: Any] {
                return dictionary
            }
        }

        return [:]
    }
}
