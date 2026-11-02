import Foundation

public enum SafetyPolicy {
    public static func validate(_ item: CleanupItem, home: URL = FileManager.default.homeDirectoryForCurrentUser, control: ScanControl = ScanControl()) throws {
        let url = Paths.normalized(item.url)
        let path = url.path
        let protected = ["/", "/Applications", "/Users", "/Library", "/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var", "/dev", "/Volumes", "/cores", "/opt", home.path,
                         home.appendingPathComponent("Library").path,
                         home.appendingPathComponent(".Trash").path]
        let protectedTrees = ["/System", "/bin", "/sbin", "/usr", "/private", "/etc", "/var", "/dev", "/Library", home.appendingPathComponent(".Trash").path,
                              home.appendingPathComponent("Library/Keychains").path,
                              home.appendingPathComponent("Library/Application Support/MacClean").path]
        guard !protected.contains(path), !protectedTrees.contains(where: { Paths.isInside(url, root: URL(fileURLWithPath: $0)) }) else {
            throw MCError.invalid("受保护的位置，无法清理：\(path)")
        }
        // Reject symlinks in every ancestor, including a parent swapped since the scan.
        var cursor = url
        while cursor.path != "/" {
            if let stamp = try? FileStamp(url: cursor), stamp.isSymlink {
                throw MCError.invalid("为避免清理链接指向的数据，请选择原始文件：\(cursor.path)")
            }
            cursor.deleteLastPathComponent()
        }
        let current = try FileStamp(url: url)
        guard current.sameIdentity(as: item.stamp), current == item.stamp else { throw MCError.changed(path) }
        if let proof = item.duplicateProof {
            guard proof.retainedURL.path != url.path,
                  let retained = try? FileStamp(url: proof.retainedURL), retained == proof.retainedStamp,
                  retained.isRegular, !retained.sameIdentity(as: current),
                  try DuplicateFinder.sha256(proof.retainedURL, control: control) == proof.digest,
                  try DuplicateFinder.sha256(url, control: control) == proof.digest,
                  try FileStamp(url: proof.retainedURL) == retained,
                  try FileStamp(url: url) == current else {
                throw MCError.invalid("保留副本或重复内容已变化，请重新比对后再清理")
            }
        }
        if current.isDirectory {
            guard let expected = item.treeFingerprint else { throw MCError.invalid("目录缺少完整扫描，请重新扫描后再清理") }
            let fresh = try StorageScanner.scan(root: url, control: control)
            guard fresh.skipped.isEmpty, fresh.fingerprint() == expected else { throw MCError.changed(path) }
        }
        guard !current.isSymlink, current.isDirectory || current.isRegular else { throw MCError.invalid("不支持清理该文件类型") }
    }

    public static func removingOverlaps(_ items: [CleanupItem]) -> [CleanupItem] {
        let sorted = items.sorted { $0.url.path.count < $1.url.path.count }
        var result: [CleanupItem] = []
        for item in sorted where !result.contains(where: { Paths.isInside(item.url, root: $0.url) }) { result.append(item) }
        return result
    }
}

public struct TrashRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let originalPath: String
    public let trashPath: String
    public let bytes: Int64
    public let date: Date
    public let stamp: FileStamp
    public var restoredAt: Date?
}

public struct TrashReport: Sendable {
    public let records: [TrashRecord]
    public let failures: [String]
}

public struct TrashService: Sendable {
    public let historyURL: URL
    public init(historyURL: URL? = nil) {
        self.historyURL = historyURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacClean/history.json")
    }
    public func load() throws -> [TrashRecord] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return try JSONDecoder().decode([TrashRecord].self, from: Data(contentsOf: historyURL))
    }
    private func save(_ records: [TrashRecord]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(records)
        try data.write(to: historyURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }
    public func trash(_ items: [CleanupItem], home: URL = FileManager.default.homeDirectoryForCurrentUser, control: ScanControl = ScanControl(),
                      progress: @Sendable (ScanProgress) -> Void = { _ in }) -> TrashReport {
        let fm = FileManager.default
        var history: [TrashRecord]
        do { history = try load(); try save(history) }
        catch { return TrashReport(records: [], failures: ["无法写入恢复记录，已取消清理：\(error.localizedDescription)"]) }
        var moved: [TrashRecord] = [], failures: [String] = []
        for item in SafetyPolicy.removingOverlaps(items) {
            do {
                try control.check()
                progress(ScanProgress(path: item.url.path, count: moved.count, bytes: moved.reduce(0) { $0 + $1.bytes }))
                try SafetyPolicy.validate(item, home: home, control: control)
                var result: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &result)
                guard let destination = result as URL? else {
                    failures.append("\(item.url.lastPathComponent) 已移到废纸篓，但系统未返回位置，请在 Finder 中恢复")
                    continue
                }
                let stamp = try FileStamp(url: destination)
                let record = TrashRecord(id: UUID(), originalPath: item.url.path, trashPath: destination.path, bytes: item.bytes, date: Date(), stamp: stamp)
                moved.append(record); history.insert(record, at: 0)
                do { try save(history) }
                catch {
                    failures.append("记录保存失败，已停止。可在 Finder 废纸篓恢复：\(destination.lastPathComponent)")
                    break
                }
            } catch MCError.cancelled { failures.append("清理已停止，未处理的项目仍保留在原处。"); break }
            catch { failures.append("\(item.url.lastPathComponent)：\(error.localizedDescription)") }
        }
        return TrashReport(records: moved, failures: failures)
    }
    public func restore(_ record: TrashRecord) throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: record.trashPath), destination = URL(fileURLWithPath: record.originalPath)
        let current = try FileStamp(url: source)
        guard current.sameIdentity(as: record.stamp) else { throw MCError.changed(record.trashPath) }
        guard !fm.fileExists(atPath: destination.path), (try? FileStamp(url: destination)) == nil else {
            throw MCError.invalid("原位置已存在同名文件，恢复不会覆盖它。请先在 Finder 中处理。")
        }
        let parent = destination.deletingLastPathComponent()
        guard let stamp = try? FileStamp(url: parent), stamp.isDirectory,
              parent.resolvingSymlinksInPath().path == parent.standardizedFileURL.path else {
            throw MCError.invalid("原文件夹不存在或路径已变化，请在 Finder 废纸篓中手动恢复")
        }
        var history = try load()
        guard let index = history.firstIndex(where: { $0.id == record.id && $0.restoredAt == nil }) else { throw MCError.invalid("找不到可恢复记录") }
        try fm.moveItem(at: source, to: destination)
        history[index].restoredAt = Date()
        try save(history)
    }
}
