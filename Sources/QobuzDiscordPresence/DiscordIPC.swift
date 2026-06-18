import Foundation
import Darwin

enum DiscordIPCError: LocalizedError {
    case discordNotFound
    case connectionFailed(String)
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .discordNotFound:
            return "Discord IPC socket not found. Open Discord and try again."
        case .connectionFailed(let path):
            return "Could not connect to Discord at \(path)."
        case .encodingFailed:
            return "Could not encode the Discord activity."
        case .writeFailed:
            return "Could not write to Discord."
        }
    }
}

actor DiscordIPC {
    private var socket: Int32 = -1
    private var connectedClientID: String?

    func publish(track: NowPlayingTrack, clientID: String) throws {
        try ensureConnected(clientID: clientID)
        try send(opcode: 1, payload: activityPayload(track: track))
    }

    func clear(clientID: String) throws {
        try ensureConnected(clientID: clientID)
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": NSNull()
            ],
            "nonce": UUID().uuidString
        ]
        try send(opcode: 1, payload: payload)
    }

    private func ensureConnected(clientID: String) throws {
        if socket >= 0, connectedClientID == clientID {
            return
        }

        closeSocket()

        guard let path = findDiscordSocketPath() else {
            throw DiscordIPCError.discordNotFound
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DiscordIPCError.connectionFailed(path)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

        guard path.utf8.count < maxPathLength else {
            Darwin.close(fd)
            throw DiscordIPCError.connectionFailed(path)
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { rebound in
                _ = path.withCString { source in
                    strncpy(rebound, source, maxPathLength)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    fd,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }

        guard connectResult == 0 else {
            Darwin.close(fd)
            throw DiscordIPCError.connectionFailed(path)
        }

        socket = fd
        connectedClientID = clientID
        try send(opcode: 0, payload: ["v": 1, "client_id": clientID])
    }

    private func send(opcode: Int32, payload: [String: Any]) throws {
        guard socket >= 0 else {
            throw DiscordIPCError.discordNotFound
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw DiscordIPCError.encodingFailed
        }

        var packet = Data()
        packet.append(littleEndianData(opcode))
        packet.append(littleEndianData(Int32(json.count)))
        packet.append(json)

        try packet.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw DiscordIPCError.writeFailed
            }

            var bytesWritten = 0
            while bytesWritten < packet.count {
                let result = Darwin.write(
                    socket,
                    baseAddress.advanced(by: bytesWritten),
                    packet.count - bytesWritten
                )

                guard result > 0 else {
                    closeSocket()
                    throw DiscordIPCError.writeFailed
                }
                bytesWritten += result
            }
        }
    }

    private func activityPayload(track: NowPlayingTrack) -> [String: Any] {
        var activity: [String: Any] = [
            "name": "Qobuz",
            "details": track.title,
            "state": track.artist ?? "Qobuz",
            "type": 2,
            "instance": false
        ]

        var assets: [String: String] = [:]

        if let artworkURL = track.artworkURL, !artworkURL.isEmpty {
            assets["large_image"] = artworkURL
        } else {
            assets["large_image"] = "discord-large-image"
        }

        if let album = track.album, !album.isEmpty {
            assets["large_text"] = album
        }

        assets["small_image"] = "discord-small-image"
        assets["small_text"] = "Qobuz"

        if !assets.isEmpty {
            activity["assets"] = assets
        }

        if track.isPlaying,
           let duration = track.duration,
           duration > 0,
           let elapsed = track.elapsed {
            let now = Date().timeIntervalSince1970
            activity["timestamps"] = [
                "start": Int(now - elapsed),
                "end": Int(now + max(0, duration - elapsed))
            ]
        }

        return [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": activity
            ],
            "nonce": UUID().uuidString
        ]
    }

    private func closeSocket() {
        if socket >= 0 {
            Darwin.close(socket)
        }
        socket = -1
        connectedClientID = nil
    }

    private func littleEndianData(_ value: Int32) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<Int32>.size)
    }

    private func findDiscordSocketPath() -> String? {
        let fileManager = FileManager.default
        let candidateDirectories = [
            ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"],
            ProcessInfo.processInfo.environment["TMPDIR"],
            ProcessInfo.processInfo.environment["TMP"],
            ProcessInfo.processInfo.environment["TEMP"],
            "/tmp"
        ].compactMap { $0 }

        for directory in candidateDirectories {
            for index in 0...9 {
                let path = URL(fileURLWithPath: directory)
                    .appendingPathComponent("discord-ipc-\(index)")
                    .path
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }
        }

        return nil
    }
}
