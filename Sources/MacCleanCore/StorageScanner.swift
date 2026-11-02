import Foundation
import Darwin

public enum StorageScanner {
    /// An explicit stack keeps deep directory trees off the call stack. Symlinks are never followed.
    public static func scan(root input: URL, control: ScanControl = ScanControl(),
                            progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> StorageScan {
        let root = Paths.normalized(input)
        let start = Date(), fm = FileManager.default
        let initial = try FileStamp(url: root)
        guard !initial.isSymlink else { throw MCError.invalid("请选择实际文件夹，不要选择符号链接") }
        var nodes: [String: FileNode] = [:], skipped: [String] = [], order: [String] = []
        var stack = [root], count = 0, bytes: Int64 = 0
        var seen: Set<String> = []
        let excluded = ["/dev", "/net", "/Network", "/Volumes", "/System/Volumes"]
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        while let url = stack.popLast() {
            try control.check()
            do {
                let stamp = try FileStamp(url: url)
                var info = stat()
                guard url.path.withCString({ lstat($0, &info) }) == 0 else { throw MCError.denied(url.path) }
                let identity = "\(stamp.device):\(stamp.inode)"
                let duplicateLink = stamp.isRegular && !seen.insert(identity).inserted
                let resources = try? url.resourceValues(forKeys: keys)
                let cloudOnly = (info.st_flags & 0x40000000) != 0 || (resources?.isUbiquitousItem == true && resources?.ubiquitousItemDownloadingStatus == .notDownloaded)
                let allocated = duplicateLink || stamp.isSymlink ? 0 : max(0, Int64(info.st_blocks) * 512)
                var node = FileNode(url: url, stamp: stamp, bytes: allocated,
                                    logicalBytes: stamp.isRegular ? stamp.logicalSize : 0,
                                    fileCount: stamp.isDirectory ? 0 : 1, children: [], unreadable: false,
                                    latestModified: Date(timeIntervalSince1970: Double(stamp.modifiedSeconds)), cloudOnly: cloudOnly)
                if stamp.isDirectory {
                    if url != root && excluded.contains(url.path) {
                        node.unreadable = true; skipped.append(url.path + "（挂载点 / 重复卷）")
                    } else {
                        do {
                            let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                            node.children = children.map(\.path)
                            stack.append(contentsOf: children.reversed())
                        } catch { node.unreadable = true; skipped.append(url.path) }
                    }
                }
                nodes[url.path] = node; order.append(url.path)
                count += 1; bytes += allocated
                if count % 300 == 0 { progress(ScanProgress(path: url.path, count: count, bytes: bytes)) }
            } catch { skipped.append(url.path) }
        }
        for path in order.reversed() {
            guard var node = nodes[path], node.isDirectory else { continue }
            for child in node.children {
                guard let value = nodes[child] else { node.unreadable = true; continue }
                node.bytes += value.bytes; node.logicalBytes += value.logicalBytes; node.fileCount += value.fileCount
                node.latestModified = max(node.latestModified, value.latestModified)
                node.unreadable = node.unreadable || value.unreadable
            }
            nodes[path] = node
        }
        try control.check()
        progress(ScanProgress(path: root.path, count: count, bytes: nodes[root.path]?.bytes ?? 0))
        return StorageScan(root: root, nodes: nodes, skipped: skipped, started: start, completed: Date())
    }
}
