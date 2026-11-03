import Foundation
import CryptoKit

public struct FileDigest: Codable, Sendable {
    let stamp: FileStamp
    let digest: String
}

public struct DuplicateScan: Codable, Sendable {
    public let groups: [DuplicateGroup]
    public let digests: [String: FileDigest]
    public let hashedCount: Int
}

public enum DuplicateFinder {
    public static func find(in scan: StorageScan, minimumSize: Int64 = 1_048_576,
                            control: ScanControl = ScanControl(), progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [DuplicateGroup] {
        try compare(in: scan, minimumSize: minimumSize, control: control, progress: progress).groups
    }

    public static func compare(in scan: StorageScan, previous: [String: FileDigest] = [:],
                               minimumSize: Int64 = 1_048_576, control: ScanControl = ScanControl(),
                               progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> DuplicateScan {
        let candidates = scan.files.filter { $0.logicalBytes >= minimumSize && !$0.cloudOnly && $0.bytes > 0 &&
            !$0.url.pathComponents.contains(".Trash") && !$0.url.pathComponents.contains(".Trashes") }
        let buckets = Dictionary(grouping: candidates, by: \.logicalBytes).values.filter { $0.count > 1 }
        var hashes: [String: [FileNode]] = [:]
        var digests: [String: FileDigest] = [:]
        var count = 0, hashedCount = 0
        for file in candidates {
            if let cached = previous[file.id], cached.stamp == file.stamp { digests[file.id] = cached }
        }
        for bucket in buckets {
            for file in bucket {
                try control.check()
                guard let before = try? FileStamp(url: file.url), before == file.stamp else { continue }
                let digest: String
                if let cached = digests[file.id] { digest = cached.digest }
                else {
                    do { digest = try sha256(file.url, control: control); hashedCount += 1 }
                    catch MCError.cancelled { throw MCError.cancelled }
                    catch { continue }
                }
                guard let after = try? FileStamp(url: file.url), after == before else { continue }
                digests[file.id] = FileDigest(stamp: after, digest: digest)
                hashes[digest, default: []].append(file); count += 1
                progress(ScanProgress(path: file.url.path, count: count, bytes: 0))
            }
        }
        let groups: [DuplicateGroup] = hashes.compactMap { digest, files in
            guard files.count > 1 else { return nil }
            // The first, newest copy is always retained by the UI's duplicate selection action.
            let sorted = files.sorted {
                $0.stamp.modifiedSeconds == $1.stamp.modifiedSeconds ? $0.url.path < $1.url.path : $0.stamp.modifiedSeconds > $1.stamp.modifiedSeconds
            }
            return DuplicateGroup(digest: digest, files: sorted)
        }.sorted { $0.reclaimable > $1.reclaimable }
        return DuplicateScan(groups: groups, digests: digests, hashedCount: hashedCount)
    }
    public static func sha256(_ url: URL, control: ScanControl = ScanControl()) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try control.check()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
