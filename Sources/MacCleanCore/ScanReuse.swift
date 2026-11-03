import Foundation

/// Each run records only the roots it actually read. Deleted or unneeded roots
/// naturally fall out of the next snapshot.
public final class ScanReuse {
    private let previous: [String: StorageScan]
    public private(set) var results: [String: StorageScan] = [:]

    public init(previous: [String: StorageScan] = [:]) {
        self.previous = previous
    }

    func scan(root: URL, control: ScanControl, progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> StorageScan {
        let key = Paths.normalized(root).path
        let result = try StorageScanner.scan(root: root, previous: previous[key], control: control, progress: progress)
        results[key] = result
        return result
    }
}

public struct SnapshotStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func read<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        let url = directory.appendingPathComponent(key + ".json")
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func write<Value: Encodable>(_ value: Value, key: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(key + ".json")
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
