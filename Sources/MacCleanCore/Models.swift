import Foundation
import Darwin
import CryptoKit

public enum MCError: LocalizedError {
    case cancelled, denied(String), changed(String), invalid(String)
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "扫描已取消"
        case .denied(let path): return "无法访问：\(path)"
        case .changed(let path): return "文件在扫描后已变化，请重新扫描：\(path)"
        case .invalid(let reason): return reason
        }
    }
}

public final class ScanControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public func check() throws {
        lock.lock(); let value = stopped; lock.unlock()
        if value { throw MCError.cancelled }
    }
}

public struct FileStamp: Codable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public let logicalSize: Int64
    public let mode: UInt16
    public init(url: URL) throws {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else { throw MCError.denied(url.path) }
        device = UInt64(UInt32(bitPattern: info.st_dev)); inode = UInt64(info.st_ino)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        logicalSize = info.st_size; mode = info.st_mode
    }
    public var isDirectory: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFDIR) }
    public var isRegular: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFREG) }
    public var isSymlink: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFLNK) }
    public func sameIdentity(as other: Self) -> Bool {
        device == other.device && inode == other.inode && mode == other.mode
    }
}

public struct FileNode: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let stamp: FileStamp
    public var bytes: Int64
    public var logicalBytes: Int64
    public var fileCount: Int
    public var children: [String]
    public var unreadable: Bool
    public var latestModified: Date
    public let cloudOnly: Bool
    public var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    public var isDirectory: Bool { stamp.isDirectory }
}

public struct ScanProgress: Sendable {
    public let path: String
    public let count: Int
    public let bytes: Int64
    public init(path: String, count: Int, bytes: Int64) { self.path = path; self.count = count; self.bytes = bytes }
}

public struct StorageScan: Sendable {
    public let root: URL
    public let nodes: [String: FileNode]
    public let skipped: [String]
    public let started: Date
    public let completed: Date
    public var total: Int64 { nodes[root.path]?.bytes ?? 0 }
    public var files: [FileNode] { nodes.values.filter { $0.stamp.isRegular } }
    public func fingerprint(under rootURL: URL? = nil) -> String {
        let base = rootURL ?? root
        var hash = SHA256()
        for key in nodes.keys.sorted() where Paths.isInside(URL(fileURLWithPath: key), root: base) {
            let node = nodes[key]!, stamp = node.stamp
            let line = "\(key)\u{0}\(stamp.device):\(stamp.inode):\(stamp.mode):\(stamp.logicalSize):\(stamp.modifiedSeconds):\(stamp.modifiedNanos):\(node.unreadable)\n"
            hash.update(data: Data(line.utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public func children(of path: String) -> [FileNode] {
        (nodes[path]?.children ?? []).compactMap { nodes[$0] }.sorted {
            $0.bytes == $1.bytes ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.bytes > $1.bytes
        }
    }
}

public struct DuplicateProof: Sendable {
    public let retainedURL: URL
    public let retainedStamp: FileStamp
    public let digest: String
    public init(retainedURL: URL, retainedStamp: FileStamp, digest: String) {
        self.retainedURL = retainedURL; self.retainedStamp = retainedStamp; self.digest = digest
    }
}

public struct CleanupItem: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let category: String
    public let reason: String
    public let recommended: Bool
    public let stamp: FileStamp
    public let treeFingerprint: String?
    public let duplicateProof: DuplicateProof?
    public init(url: URL, bytes: Int64, category: String, reason: String, recommended: Bool, stamp: FileStamp, treeFingerprint: String? = nil, duplicateProof: DuplicateProof? = nil) {
        self.url = url; self.bytes = bytes; self.category = category; self.reason = reason
        self.recommended = recommended; self.stamp = stamp; self.treeFingerprint = treeFingerprint; self.duplicateProof = duplicateProof
    }
}

public struct CleanupScan: Sendable {
    public let items: [CleanupItem]
    public let skipped: [String]
}

public struct AppFootprint: Identifiable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let bundleID: String
    public let version: String
    public let bundle: CleanupItem
    public let related: [CleanupItem]
    public let skippedCount: Int
    public var bytes: Int64 { bundle.bytes + related.reduce(0) { $0 + $1.bytes } }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public var id: String { digest }
    public let digest: String
    public let files: [FileNode]
    public var reclaimable: Int64 { files.dropFirst().reduce(0) { $0 + $1.bytes } }
}

public enum Paths {
    public static func normalized(_ url: URL) -> URL { url.standardizedFileURL }
    public static func isInside(_ url: URL, root: URL) -> Bool {
        let path = normalized(url).path, base = normalized(root).path
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }
    public static func short(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path == home ? "~" : (url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path)
    }
}
