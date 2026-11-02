import SwiftUI
import AppKit
import MacCleanCore

struct SectionItem: Identifiable {
    let id: Page
    let title: String
    let symbol: String
}

enum Page: String, CaseIterable {
    case overview, storage, apps, cleanup, duplicates, history, settings
    var title: String {
        switch self {
        case .overview: return "空间概览"
        case .storage: return "存储空间"
        case .apps: return "应用管理"
        case .cleanup: return "垃圾清理"
        case .duplicates: return "重复文件"
        case .history: return "清理记录"
        case .settings: return "偏好设置"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .storage: return "internaldrive"
        case .apps: return "square.stack.3d.up"
        case .cleanup: return "sparkles"
        case .duplicates: return "doc.on.doc"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@MainActor final class AppModel: ObservableObject {
    @Published var page: Page = .overview
    @Published var busy = false
    @Published var canCancel = true
    @Published var operation = ""
    @Published var progressPath = ""
    @Published var scannedCount = 0
    @Published var storage: StorageScan?
    @Published var browserPath = ""
    @Published var chosenRoot = FileManager.default.homeDirectoryForCurrentUser
    @Published var apps: [AppFootprint] = []
    @Published var hasAppScan = false
    @Published var cleanup: [CleanupItem] = []
    @Published var hasCleanupScan = false
    @Published var cleanupSkipped: [String] = []
    @Published var cleanupSelection: Set<String> = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var hasDuplicateScan = false
    @Published var duplicateSelection: Set<String> = []
    @Published var duplicateRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var history: [TrashRecord] = []
    @Published var totalCapacity: Int64 = 0
    @Published var availableCapacity: Int64 = 0
    @Published var notice: String?
    @Published var details: [String] = []
    @Published var showingDetails = false
    @Published var pending: [CleanupItem] = []
    @Published var showingReview = false
    @Published var ignoredPaths: Set<String>
    @Published var lastCleaned: Int64 = 0
    let trashService = TrashService()
    private var control: ScanControl?

    init() {
        ignoredPaths = Set(UserDefaults.standard.stringArray(forKey: "ignoredPaths") ?? [])
        refreshDisk(); loadHistory()
        if CommandLine.arguments.contains("--capture") {
            if let index = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.count > index + 1,
               let requestedPage = Page(rawValue: CommandLine.arguments[index + 1]) { page = requestedPage }
            if let index = CommandLine.arguments.firstIndex(of: "--scan-path"), CommandLine.arguments.count > index + 1 {
                chosenRoot = URL(fileURLWithPath: CommandLine.arguments[index + 1]); page = .storage; scanStorage()
            }
        }
    }
    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    var visibleCleanup: [CleanupItem] { cleanup.filter { !ignoredPaths.contains($0.id) } }
    var recommendedBytes: Int64 { visibleCleanup.filter(\.recommended).reduce(0) { $0 + $1.bytes } }
    var cleanupSelectedBytes: Int64 { visibleCleanup.filter { cleanupSelection.contains($0.id) }.reduce(0) { $0 + $1.bytes } }
    var pendingBytes: Int64 { pending.reduce(0) { $0 + $1.bytes } }
    var runningIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    func refreshDisk() {
        if let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
            availableCapacity = Int64(values.volumeAvailableCapacity ?? 0)
        }
    }
    func loadHistory() {
        do { history = try trashService.load() }
        catch { notice = "清理记录读取失败：\(error.localizedDescription)" }
    }
    func chooseFolder(forDuplicates: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "选择文件夹"; panel.directoryURL = forDuplicates ? duplicateRoot : chosenRoot
        if panel.runModal() == .OK, let url = panel.url {
            if forDuplicates { duplicateRoot = url; scanDuplicates() }
            else { chosenRoot = url; page = .storage; scanStorage() }
        }
    }
    private func begin(_ title: String, cancellable: Bool = true) -> ScanControl? {
        guard !busy else { return nil }
        busy = true; canCancel = cancellable; operation = title; progressPath = "正在准备…"; scannedCount = 0
        notice = nil
        let value = ScanControl(); control = value; return value
    }
    private func finish(_ error: Error? = nil) {
        busy = false; control = nil
        if let error { notice = error.localizedDescription }
        refreshDisk()
    }
    func cancel() { control?.cancel(); operation = "正在停止…" }
    nonisolated private func progress(_ value: ScanProgress) {
        Task { @MainActor [weak self] in
            guard self?.busy == true else { return }
            self?.progressPath = value.path; self?.scannedCount = value.count
        }
    }
    func scanStorage() {
        guard let control = begin("正在分析存储空间") else { return }
        let root = chosenRoot
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try StorageScanner.scan(root: root, control: control) { self.progress($0) }
                }.value
                storage = result; browserPath = root.path; finish()
                if !result.skipped.isEmpty { notice = "有 \(result.skipped.count) 个位置未读取。结果仅包含可访问内容。" }
            } catch { finish(error) }
        }
    }
    func scanCleanup() {
        guard let control = begin("正在查找可清理项目") else { return }
        let ids = runningIDs
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try CleanupScanner.scan(runningBundleIDs: ids, control: control) { self.progress($0) }
                }.value
                cleanup = result.items; cleanupSkipped = result.skipped; hasCleanupScan = true
                cleanupSelection = Set(visibleCleanup.filter(\.recommended).map(\.id)); finish()
                if !result.skipped.isEmpty { notice = "有 \(result.skipped.count) 个位置未读取，可查看扫描详情。" }
            } catch { finish(error) }
        }
    }
    func scanApps() {
        guard let control = begin("正在统计应用占用") else { return }
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try AppScanner.scan(control: control) { self.progress($0) }
                }.value
                apps = result; hasAppScan = true; finish()
            } catch { finish(error) }
        }
    }
    func scanDuplicates() {
        guard let control = begin("正在比对重复文件") else { return }
        let root = duplicateRoot
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    let scan = try StorageScanner.scan(root: root, control: control) { self.progress($0) }
                    let groups = try DuplicateFinder.find(in: scan, control: control) { self.progress($0) }
                    return (groups, scan.skipped)
                }.value
                duplicates = result.0; hasDuplicateScan = true; duplicateSelection = []; finish()
                if !result.1.isEmpty { notice = "有 \(result.1.count) 个位置未读取，未参与重复比对。" }
            } catch { finish(error) }
        }
    }
    func requestTrash(_ items: [CleanupItem]) {
        guard !busy, !items.isEmpty else { return }
        pending = SafetyPolicy.removingOverlaps(items); showingReview = true
    }
    func item(for node: FileNode) -> CleanupItem {
        CleanupItem(url: node.url, bytes: node.bytes, category: "手动选择", reason: "存储空间中手动选择的文件", recommended: false, stamp: node.stamp, treeFingerprint: node.isDirectory ? storage?.fingerprint(under: node.url) : nil)
    }
    func trashDuplicates() {
        let items = duplicates.flatMap { group -> [CleanupItem] in
            guard let retained = group.files.first else { return [] }
            let proof = DuplicateProof(retainedURL: retained.url, retainedStamp: retained.stamp, digest: group.digest)
            return group.files.dropFirst().filter { duplicateSelection.contains($0.id) }.map { node in
                CleanupItem(url: node.url, bytes: node.bytes, category: "重复副本", reason: "与保留副本内容一致", recommended: false, stamp: node.stamp, duplicateProof: proof)
            }
        }
        requestTrash(items)
    }
    func confirmTrash() {
        showingReview = false
        guard let control = begin("正在移到废纸篓") else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        let candidates = pending
        let blocked = candidates.filter { item in running.contains { Paths.isInside(item.url, root: $0) || Paths.isInside($0, root: item.url) } }
        let ids = runningIDs
        let activeData = candidates.filter { item in ids.contains { id in
            item.url.lastPathComponent == id || item.url.lastPathComponent == id + ".plist" || item.url.lastPathComponent == id + ".savedState"
        } }
        let blockedIDs = Set((blocked + activeData).map(\.id))
        let items = candidates.filter { !blockedIDs.contains($0.id) }
        let service = trashService
        Task {
            let report = await Task.detached(priority: .userInitiated) { [self] in service.trash(items, control: control) { self.progress($0) } }.value
            let moved = Set(report.records.map(\.originalPath))
            lastCleaned = report.records.reduce(0) { $0 + $1.bytes }
            cleanup.removeAll { moved.contains($0.id) }; cleanupSelection.subtract(moved)
            apps.removeAll { moved.contains($0.id) }
            // Descendant totals and hashes are now stale; require a fresh scan.
            storage = nil; hasDuplicateScan = false; duplicates = []; duplicateSelection = []
            hasAppScan = false; apps = []
            pending = []; loadHistory(); finish()
            let failures = report.failures + (blockedIDs.isEmpty ? [] : ["已跳过 \(blockedIDs.count) 个正在运行的应用 / 关联项目，请退出应用后重新扫描。"])
            notice = "已将 \(report.records.count) 项（\(sizeText(lastCleaned))）移到废纸篓。清空废纸篓后才会释放空间。"
            if !failures.isEmpty { details = failures; showingDetails = true }
        }
    }
    func restore(_ record: TrashRecord) {
        guard let _ = begin("正在恢复文件", cancellable: false) else { return }
        let service = trashService
        Task {
            do {
                try await Task.detached { try service.restore(record) }.value
                loadHistory(); storage = nil; hasCleanupScan = false; hasAppScan = false; hasDuplicateScan = false
                cleanup = []; cleanupSelection = []; apps = []; duplicates = []; duplicateSelection = []
                finish(); notice = "已恢复到原位置：\(record.originalPath)"
            } catch { finish(error) }
        }
    }
    func ignore(_ path: String) {
        ignoredPaths.insert(path); cleanupSelection.remove(path); saveIgnored()
    }
    func unignore(_ path: String) { ignoredPaths.remove(path); saveIgnored() }
    private func saveIgnored() { UserDefaults.standard.set(Array(ignoredPaths).sorted(), forKey: "ignoredPaths") }
    func showDetails(_ lines: [String]) { details = lines; showingDetails = true }
    func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    func openTrash() { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
