import Foundation

/// Plain-text diagnostic log written to the shared App Group container so it can be
/// inspected directly on disk without touching Keychain-stored credentials.
actor DebugLog {
    static let shared = DebugLog()

    private let maximumBytes = 256 * 1024
    private let retainedBytes = 128 * 1024

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("debug.log")
    }

    func append(_ message: String) {
        guard let url = fileURL else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        rotateIfNeeded(url)

        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func rotateIfNeeded(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maximumBytes,
              let data = try? Data(contentsOf: url) else { return }

        let suffix = data.suffix(retainedBytes)
        let firstNewline = suffix.firstIndex(of: 0x0A)
        let start = firstNewline.map { suffix.index(after: $0) } ?? suffix.startIndex
        try? Data(suffix[start...]).write(to: url, options: .atomic)
    }
}
