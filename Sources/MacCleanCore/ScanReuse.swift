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
        let legacy = directory.appendingPathComponent(key + ".json")
        let compressed = legacy.appendingPathExtension("lz4")
        let data: Data
        do {
            let bytes = try NSData(contentsOf: compressed, options: .mappedIfSafe)
            data = try bytes.decompressed(using: .lz4) as Data
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            do {
                data = try Data(contentsOf: legacy, options: .mappedIfSafe)
            } catch let missing as CocoaError where missing.code == .fileReadNoSuchFile {
                return nil
            }
        }
        return try JSONDecoder().decode(type, from: data)
    }

    public func write<Value: Encodable>(_ value: Value, key: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let legacy = directory.appendingPathComponent(key + ".json")
        let url = legacy.appendingPathExtension("lz4")
        let encoded = try JSONEncoder().encode(value) as NSData
        let compressed = try encoded.compressed(using: .lz4)
        try compressed.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if fm.fileExists(atPath: legacy.path) { try fm.removeItem(at: legacy) }
    }
}
