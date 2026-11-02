import Foundation

public enum CleanupScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            runningBundleIDs: Set<String> = [], control: ScanControl = ScanControl(),
                            now: Date = Date(), progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> CleanupScan {
        let fm = FileManager.default
        // No cookies, browser sessions, keychains, mail, or app documents are part of these rules.
        let rules: [(String, String, Int, Bool)] = [
            ("Library/Caches", "应用缓存", 14, true),
            ("Library/Logs", "旧日志", 14, true),
            ("Library/Developer/Xcode/DerivedData", "开发缓存", 30, false)
        ]
        var items: [CleanupItem] = [], skipped: [String] = []
        for (relative, category, days, recommended) in rules {
            try control.check()
            let directory = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: directory.path) else { continue }
            let children: [URL]
            do { children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
            catch { skipped.append(directory.path); continue }
            for url in children {
                try control.check()
                if runningBundleIDs.contains(where: { url.lastPathComponent == $0 || url.lastPathComponent.hasPrefix($0 + ".") }) { continue }
                guard let stamp = try? FileStamp(url: url), !stamp.isSymlink else { continue }
                let result = try StorageScanner.scan(root: url, control: control, progress: progress)
                skipped.append(contentsOf: result.skipped)
                guard let node = result.nodes[url.path], !node.unreadable, node.bytes > 0,
                      node.latestModified < now.addingTimeInterval(-Double(days) * 86400) else { continue }
                items.append(CleanupItem(url: url, bytes: node.bytes, category: category,
                                         reason: "至少 \(days) 天未修改，可由对应应用重新生成", recommended: recommended, stamp: stamp, treeFingerprint: stamp.isDirectory ? result.fingerprint() : nil))
            }
        }
        let downloads = home.appendingPathComponent("Downloads")
        if fm.fileExists(atPath: downloads.path) {
            do {
                for url in try fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil) {
                    try control.check()
                    guard let stamp = try? FileStamp(url: url), stamp.isRegular else { continue }
                    let age = now.timeIntervalSince1970 - Double(stamp.modifiedSeconds)
                    let installer = ["dmg", "pkg", "iso"].contains(url.pathExtension.lowercased())
                    guard age > Double(installer ? 30 : 90) * 86400 else { continue }
                    let scan = try StorageScanner.scan(root: url, control: control)
                    items.append(CleanupItem(url: url, bytes: scan.total, category: installer ? "旧安装包" : "旧下载",
                                             reason: installer ? "超过 30 天的安装包，请确认已不需要" : "超过 90 天未修改，请确认已不需要",
                                             recommended: false, stamp: stamp))
                }
            } catch MCError.cancelled { throw MCError.cancelled }
            catch { skipped.append(downloads.path) }
        }
        return CleanupScan(items: items.sorted { $0.bytes > $1.bytes }, skipped: Array(Set(skipped)).sorted())
    }
}
