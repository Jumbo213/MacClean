import Foundation

public enum AppScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            directories: [URL]? = nil, control: ScanControl = ScanControl(),
                            progress: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [AppFootprint] {
        let fm = FileManager.default
        let roots = directories ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
        var urls: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                try control.check()
                if url.pathExtension == "app" { urls.append(url); enumerator.skipDescendants() }
            }
        }
        var apps: [AppFootprint] = []
        for url in urls {
            try control.check(); progress(ScanProgress(path: url.path, count: apps.count, bytes: 0))
            guard let bundle = Bundle(url: url), let stamp = try? FileStamp(url: url), !stamp.isSymlink else { continue }
            let id = bundle.bundleIdentifier ?? ""
            let validID = !id.isEmpty && !id.contains("/") && id != "." && id != ".."
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
            let scan = try StorageScanner.scan(root: url, control: control)
            let appItem = CleanupItem(url: url, bytes: scan.total, category: "应用本体", reason: "应用程序", recommended: false, stamp: stamp, treeFingerprint: scan.fingerprint())
            let paths = validID ? ["Library/Caches/\(id)", "Library/Application Support/\(id)", "Library/Containers/\(id)", "Library/Preferences/\(id).plist", "Library/Logs/\(id)", "Library/WebKit/\(id)", "Library/Saved Application State/\(id).savedState"] : []
            var related: [CleanupItem] = []; var skipped = scan.skipped.count
            for path in paths {
                let file = home.appendingPathComponent(path)
                guard fm.fileExists(atPath: file.path), let relatedStamp = try? FileStamp(url: file), !relatedStamp.isSymlink else { continue }
                let value = try StorageScanner.scan(root: file, control: control)
                skipped += value.skipped.count
                related.append(CleanupItem(url: file, bytes: value.total, category: "关联数据", reason: "标识符精确匹配 \(id)；可能包含个人数据", recommended: false, stamp: relatedStamp, treeFingerprint: relatedStamp.isDirectory ? value.fingerprint() : nil))
            }
            apps.append(AppFootprint(name: name, url: url, bundleID: id, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—", bundle: appItem, related: related, skippedCount: skipped))
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }
}
