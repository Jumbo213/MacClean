import Foundation
import Darwin

public struct FileMove: Sendable {
    public let source: URL
    public let destination: URL
    public init(source: URL, destination: URL) { self.source = source; self.destination = destination }
}

/// Reuses the scan tree after a known move. No full-volume enumeration or content hashing.
public enum ScanUpdater {
    public static func applying(_ moves: [FileMove], to scan: StorageScan,
                                control: ScanControl = ScanControl()) throws -> StorageScan {
        guard !moves.isEmpty else { return scan }
        var nodes = scan.nodes
        var touched: Set<String> = []
        for move in moves {
            try control.check()
            let old = Paths.normalized(move.source), new = Paths.normalized(move.destination)
            let branch = nodes.values.filter { Paths.isInside($0.url, root: old) }
            for node in branch { nodes.removeValue(forKey: node.id) }
            if Paths.isInside(new, root: scan.root) {
                if !branch.isEmpty {
                    for node in branch {
                        let suffix = String(node.id.dropFirst(old.path.count))
                        let url = URL(fileURLWithPath: new.path + suffix)
                        let children = node.children.map { new.path + String($0.dropFirst(old.path.count)) }
                        let stamp = node.id == old.path ? (try FileStamp(url: url)) : node.stamp
                        nodes[url.path] = FileNode(url: url, stamp: stamp, bytes: node.bytes, logicalBytes: node.logicalBytes,
                                                   fileCount: node.fileCount, children: children, unreadable: node.unreadable,
                                                   latestModified: node.latestModified, cloudOnly: node.cloudOnly)
                    }
                } else if (try? FileStamp(url: new)) != nil {
                    let added = try StorageScanner.scan(root: new, control: control)
                    nodes.merge(added.nodes) { _, fresh in fresh }
                }
            }
            for url in [old, new] {
                var parent = url.deletingLastPathComponent()
                while Paths.isInside(parent, root: scan.root) {
                    touched.insert(parent.path)
                    if parent == scan.root { break }
                    parent.deleteLastPathComponent()
                }
            }
        }
        return try rebuild(nodes, original: scan, touched: touched, control: control)
    }

    /// Used for restored or externally changed items. Only these subtrees are enumerated.
    public static func refreshing(_ paths: [URL], in scan: StorageScan,
                                  control: ScanControl = ScanControl()) throws -> StorageScan {
        var nodes = scan.nodes, touched: Set<String> = []
        for url in paths where Paths.isInside(url, root: scan.root) {
            try control.check()
            let removed = nodes.values.filter { Paths.isInside($0.url, root: url) }.map(\.id)
            for path in removed { nodes.removeValue(forKey: path) }
            if let stamp = try? FileStamp(url: url), !stamp.isSymlink {
                let updated = try StorageScanner.scan(root: url, control: control)
                nodes.merge(updated.nodes) { _, fresh in fresh }
            }
            var parent = url.deletingLastPathComponent()
            while Paths.isInside(parent, root: scan.root) {
                touched.insert(parent.path)
                if parent == scan.root { break }; parent.deleteLastPathComponent()
            }
        }
        return try rebuild(nodes, original: scan, touched: touched, control: control)
    }

    private static func rebuild(_ input: [String: FileNode], original: StorageScan,
                                touched: Set<String>, control: ScanControl) throws -> StorageScan {
        var nodes = input
        // Refresh ancestor metadata so a second cleanup does not see our own deletion as an external edit.
        for path in touched {
            try control.check()
            let url = URL(fileURLWithPath: path)
            guard let stamp = try? FileStamp(url: url), stamp.isDirectory else { continue }
            var info = stat(); _ = path.withCString { lstat($0, &info) }
            let old = nodes[path]
            nodes[path] = FileNode(url: url, stamp: stamp, bytes: max(0, Int64(info.st_blocks) * 512), logicalBytes: 0,
                                   fileCount: 0, children: old?.children ?? [], unreadable: old?.unreadable ?? true,
                                   latestModified: Date(timeIntervalSince1970: Double(stamp.modifiedSeconds)), cloudOnly: false)
        }
        // Rebuild links from cached nodes; newly created Trash ancestors are included without scanning siblings.
        var children: [String: [String]] = [:]
        for path in nodes.keys where path != original.root.path {
            children[URL(fileURLWithPath: path).deletingLastPathComponent().path, default: []].append(path)
        }
        // Reassign hard-link allocation when the previously counted link leaves the scanned scope.
        let hardLinks = Dictionary(grouping: nodes.values.filter { $0.stamp.isRegular }, by: { "\($0.stamp.device):\($0.stamp.inode)" })
        for group in hardLinks.values {
            guard let first = group.sorted(by: { $0.id < $1.id }).first else { continue }
            let allocated = group.map(\.bytes).max() ?? 0
            var info = stat()
            let needsAllocation = group.count > 1 || allocated == 0
            let currentAllocated = needsAllocation && first.url.path.withCString { lstat($0, &info) } == 0 ? max(0, Int64(info.st_blocks) * 512) : allocated
            for node in group {
                var value = node; value.bytes = node.id == first.id ? currentAllocated : 0; nodes[node.id] = value
            }
        }
        for path in nodes.keys.sorted(by: { $0.count > $1.count }) {
            guard var node = nodes[path], node.isDirectory else { continue }
            let previousChildren = input[path]?.children ?? []
            if input[path] == nil || (touched.contains(path) && original.nodes[path] == nil) {
                if let entries = try? FileManager.default.contentsOfDirectory(at: node.url, includingPropertiesForKeys: nil) {
                    node.unreadable = Set(entries.map(\.path)) != Set(children[path] ?? [])
                }
            }
            if !touched.contains(path) {
                // Strip old aggregate values before summing the surviving children.
                node.bytes = max(0, node.bytes - previousChildren.compactMap { input[$0]?.bytes }.reduce(0, +))
            }
            node.logicalBytes = 0; node.fileCount = 0; node.children = (children[path] ?? []).sorted()
            for key in node.children {
                guard let child = nodes[key] else { continue }
                node.bytes += child.bytes; node.logicalBytes += child.logicalBytes; node.fileCount += child.fileCount
                node.latestModified = max(node.latestModified, child.latestModified); node.unreadable = node.unreadable || child.unreadable
            }
            nodes[path] = node
        }
        return StorageScan(root: original.root, nodes: nodes, skipped: original.skipped,
                           started: original.started, completed: Date())
    }

    public static func intersects(_ url: URL, changes: [URL]) -> Bool {
        changes.contains { Paths.isInside(url, root: $0) || Paths.isInside($0, root: url) }
    }

    public static func refresh(_ item: CleanupItem, changes: [URL], control: ScanControl = ScanControl()) throws -> CleanupItem? {
        guard intersects(item.url, changes: changes) else { return item }
        guard let stamp = try? FileStamp(url: item.url), !stamp.isSymlink else { return nil }
        let result = try StorageScanner.scan(root: item.url, control: control)
        guard let root = result.nodes[item.url.path] else { return nil }
        return CleanupItem(url: item.url, bytes: result.total, category: item.category, reason: item.reason,
                           recommended: item.recommended && !root.unreadable, stamp: stamp,
                           treeFingerprint: stamp.isDirectory ? result.fingerprint() : nil, duplicateProof: item.duplicateProof)
    }

    public static func refreshApps(_ apps: [AppFootprint], changes: [URL], control: ScanControl = ScanControl()) throws -> [AppFootprint] {
        var result: [AppFootprint] = []
        for app in apps {
            guard let bundle = try refresh(app.bundle, changes: changes, control: control) else { continue }
            var related: [CleanupItem] = []
            for item in app.related { if let value = try refresh(item, changes: changes, control: control) { related.append(value) } }
            result.append(AppFootprint(name: app.name, url: app.url, bundleID: app.bundleID, version: app.version,
                                       bundle: bundle, related: related, skippedCount: app.skippedCount))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    public static func refreshDuplicates(_ catalog: [DuplicateGroup], changes: [URL], control: ScanControl = ScanControl()) throws -> [DuplicateGroup] {
        var result: [DuplicateGroup] = []
        for group in catalog {
            var files: [FileNode] = []
            for file in group.files {
                try control.check()
                guard let stamp = try? FileStamp(url: file.url), stamp == file.stamp else { continue }
                if intersects(file.url, changes: changes), try DuplicateFinder.sha256(file.url, control: control) != group.digest { continue }
                files.append(file)
            }
            if files.count > 1 { result.append(DuplicateGroup(digest: group.digest, files: files)) }
        }
        return result.sorted { $0.reclaimable > $1.reclaimable }
    }
}
