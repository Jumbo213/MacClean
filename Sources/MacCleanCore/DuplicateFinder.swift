import Foundation
import CryptoKit

public enum DuplicateFinder {
    public static func find(in scan: StorageScan, minimumSize: Int64 = 1_048_576,
                            control: ScanControl = ScanControl(), progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [DuplicateGroup] {
        let candidates = scan.files.filter { $0.logicalBytes >= minimumSize && !$0.cloudOnly && $0.bytes > 0 }
        let buckets = Dictionary(grouping: candidates, by: \.logicalBytes).values.filter { $0.count > 1 }
        var hashes: [String: [FileNode]] = [:], count = 0
        for bucket in buckets {
            for file in bucket {
                try control.check()
                guard let before = try? FileStamp(url: file.url), before == file.stamp else { continue }
                let digest: String
                do { digest = try sha256(file.url, control: control) }
                catch MCError.cancelled { throw MCError.cancelled }
                catch { continue }
                guard let after = try? FileStamp(url: file.url), after == before else { continue }
                hashes[digest, default: []].append(file); count += 1
                progress(ScanProgress(path: file.url.path, count: count, bytes: 0))
            }
        }
        return hashes.compactMap { digest, files in
            guard files.count > 1 else { return nil }
            // The first, newest copy is always retained by the UI's duplicate selection action.
            let sorted = files.sorted {
                $0.stamp.modifiedSeconds == $1.stamp.modifiedSeconds ? $0.url.path < $1.url.path : $0.stamp.modifiedSeconds > $1.stamp.modifiedSeconds
            }
            return DuplicateGroup(digest: digest, files: sorted)
        }.sorted { $0.reclaimable > $1.reclaimable }
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
