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
    if bytes <= 0 { return "0 B" }
    let formatter = ByteCountFormatter(); formatter.countStyle = .file; formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}

@MainActor final class AppModel: ObservableObject {
    @Published var page: Page = .overview
    @Published var busy = false
    @Published var canCancel = true
    @Published var operation = ""
    @Published var progressPath = ""
    @Published var scannedCount = 0
    @Published var storage: StorageScan?
    @Published var browserPath = "" {
        didSet {
            if remembersBrowserPath, !browserPath.isEmpty {
                UserDefaults.standard.set(browserPath, forKey: "lastStorageBrowserPath")
            }
        }
    }
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
    @Published var hasAttemptedStorageScan = false
    @Published var mapSelectedPath: String?
    var navigationFrames: [String: CGRect] = [:]
    var mapClickLog: [String] = []
    private var cleanupCatalog: [CleanupItem] = []
    private var appCatalog: [AppFootprint] = []
    private var duplicateCatalog: [DuplicateGroup] = []
    @Published private(set) var waitingForRefresh: Set<Page> = []
    private var pendingAutoRefresh: Set<Page> = []
    private let snapshotStore: SnapshotStore?
    private let remembersBrowserPath: Bool
    private var cleanupIndex: [String: StorageScan] = [:]
    private var appIndex: [String: StorageScan] = [:]
    private var duplicateScan: StorageScan?
    private var duplicateDigests: [String: FileDigest] = [:]
    private var loadedSnapshots = false
    let trashService: TrashService
    static weak var active: AppModel?
    private var control: ScanControl?

    init(service: TrashService? = nil, store: SnapshotStore? = nil) {
        trashService = service ?? TrashService()
        remembersBrowserPath = service == nil && store == nil && !CommandLine.arguments.contains("--capture")
        snapshotStore = store ?? (service == nil && !CommandLine.arguments.contains("--capture")
            ? SnapshotStore(directory: trashService.historyURL.deletingLastPathComponent().appendingPathComponent("ScanSnapshots"))
            : nil)
        ignoredPaths = Set(UserDefaults.standard.stringArray(forKey: "ignoredPaths") ?? [])
        Self.active = self
        refreshDisk(); loadHistory()
        if CommandLine.arguments.contains("--capture") {
            if let index = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.count > index + 1,
               let requestedPage = Page(rawValue: CommandLine.arguments[index + 1]) { page = requestedPage }
            if let index = CommandLine.arguments.firstIndex(of: "--scan-path"), CommandLine.arguments.count > index + 1 {
                chosenRoot = URL(fileURLWithPath: CommandLine.arguments[index + 1]); scanStorage()
                if !CommandLine.arguments.contains("--page") { page = .storage }
            }
        }
    }
    static func forLaunch() -> AppModel {
        if let index = CommandLine.arguments.firstIndex(of: "--ui-check"), CommandLine.arguments.count > index + 1 {
            let report = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let fixture = report.deletingLastPathComponent().appendingPathComponent("MacClean-ui-fixture-" + UUID().uuidString)
            let model = AppModel(service: TrashService(historyURL: fixture.appendingPathComponent("history.json")))
            model.hasAttemptedStorageScan = true; model.page = .storage
            return model
        }
        return AppModel()
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
    func chooseFolder(forDuplicates: Bool = false, forOverview: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "选择文件夹"; panel.directoryURL = forDuplicates ? duplicateRoot : chosenRoot
        if panel.runModal() == .OK, let url = panel.url {
            if forDuplicates { duplicateRoot = url; scanDuplicates() }
            else { chosenRoot = url; page = forOverview ? .overview : .storage; scanStorage() }
        }
    }
    func chooseFolderForMap() { chooseFolder(forOverview: true) }
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
    func restoreSavedScans() async {
        guard !loadedSnapshots else { return }
        loadedSnapshots = true
        if let snapshotStore {
            guard let _ = begin("正在读取上次扫描结果", cancellable: false) else { return }
            let saved = await Task.detached(priority: .userInitiated) { SavedScans(store: snapshotStore) }.value
            if let scan = saved.storage, scan.nodes[scan.root.path] != nil {
                storage = scan
                chosenRoot = scan.root
                let savedPath = remembersBrowserPath ? UserDefaults.standard.string(forKey: "lastStorageBrowserPath") : nil
                browserPath = savedPath ?? scan.root.path
                repairBrowserPath()
                waitingForRefresh.insert(.storage)
            }
            if let saved = saved.cleanup {
                cleanup = saved.items
                cleanupCatalog = saved.items
                cleanupIndex = saved.index
                cleanupSkipped = saved.skipped
                hasCleanupScan = true
                waitingForRefresh.insert(.cleanup)
            }
            if let saved = saved.apps {
                apps = saved.items
                appCatalog = saved.items
                appIndex = saved.index
                hasAppScan = true
                waitingForRefresh.insert(.apps)
            }
            if let saved = saved.duplicates {
                duplicateRoot = saved.scan.root
                duplicateScan = saved.scan
                duplicates = saved.groups
                duplicateCatalog = saved.groups
                duplicateDigests = saved.digests
                hasDuplicateScan = true
                waitingForRefresh.insert(.duplicates)
            }
            pendingAutoRefresh = waitingForRefresh
            finish()
        }
        refreshPageIfNeeded()
    }

    var showingSavedResult: Bool {
        waitingForRefresh.contains(page == .overview ? .storage : page)
    }

    func refreshPageIfNeeded() {
        guard loadedSnapshots, !busy, !showingReview, !showingDetails else { return }
        let target = page == .overview ? Page.storage : page
        if target == .storage, !hasAttemptedStorageScan {
            scanStorage()
            return
        }
        guard pendingAutoRefresh.contains(target) else { return }
        switch target {
        case .storage: scanStorage()
        case .cleanup: scanCleanup()
        case .apps: scanApps()
        case .duplicates: scanDuplicates()
        default: break
        }
    }

    private func saveSnapshot<Value: Encodable & Sendable>(_ value: Value, key: String) async -> String? {
        guard let snapshotStore else { return nil }
        do {
            try await Task.detached(priority: .utility) { try snapshotStore.write(value, key: key) }.value
            return nil
        } catch {
            return "结果已更新，但无法保存供下次启动使用。"
        }
    }

    func scanStorage() {
        let root = chosenRoot
        let previous = storage?.root.path == root.path ? storage : nil
        guard let control = begin(previous == nil ? "正在分析存储空间" : "正在增量检查存储变化") else { return }
        pendingAutoRefresh.remove(.storage)
        hasAttemptedStorageScan = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try StorageScanner.scan(root: root, previous: previous, control: control) { self.progress($0) }
                }.value
                operation = "正在保存扫描结果"
                canCancel = false
                let warning = await saveSnapshot(result, key: SavedScans.storageKey)
                storage = result
                if previous == nil { browserPath = result.root.path }
                repairBrowserPath()
                waitingForRefresh.remove(.storage)
                finish()
                notice = warning ?? (result.skipped.isEmpty ? nil : "有 \(result.skipped.count) 个位置未读取。结果仅包含可访问内容。")
            } catch {
                if let storage { chosenRoot = storage.root }
                finish(error)
            }
        }
    }

    func scanCleanup() {
        guard let control = begin(hasCleanupScan ? "正在更新可清理项目" : "正在查找可清理项目") else { return }
        pendingAutoRefresh.remove(.cleanup)
        let ids = runningIDs, index = cleanupIndex
        let oldItems = Set(cleanup.map(\.id)), oldSelection = cleanupSelection
        let restoredSnapshot = waitingForRefresh.contains(.cleanup)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    let reuse = ScanReuse(previous: index)
                    let scan = try CleanupScanner.scan(runningBundleIDs: ids, control: control, reuse: reuse) { self.progress($0) }
                    return SavedCleanup(items: scan.items, skipped: scan.skipped, index: reuse.results)
                }.value
                canCancel = false
                let warning = await saveSnapshot(result, key: SavedScans.cleanupKey)
                cleanup = result.items; cleanupCatalog = result.items; cleanupIndex = result.index
                cleanupSkipped = result.skipped; hasCleanupScan = true
                cleanupSelection = Set(visibleCleanup.filter { item in
                    restoredSnapshot ? item.recommended : (oldItems.contains(item.id) ? oldSelection.contains(item.id) : item.recommended)
                }.map(\.id))
                waitingForRefresh.remove(.cleanup)
                finish()
                notice = warning ?? (result.skipped.isEmpty ? nil : "有 \(result.skipped.count) 个位置未读取，可查看扫描详情。")
            } catch { finish(error) }
        }
    }

    func scanApps() {
        guard let control = begin(hasAppScan ? "正在更新应用占用" : "正在统计应用占用") else { return }
        pendingAutoRefresh.remove(.apps)
        let index = appIndex
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    let reuse = ScanReuse(previous: index)
                    let items = try AppScanner.scan(control: control, reuse: reuse) { self.progress($0) }
                    return SavedApps(items: items, index: reuse.results)
                }.value
                canCancel = false
                let warning = await saveSnapshot(result, key: SavedScans.appsKey)
                apps = result.items; appCatalog = result.items; appIndex = result.index; hasAppScan = true
                waitingForRefresh.remove(.apps)
                finish()
                notice = warning
            } catch { finish(error) }
        }
    }

    func scanDuplicates() {
        let root = duplicateRoot
        let previous = duplicateScan?.root.path == root.path ? duplicateScan : nil
        let digests = previous == nil ? [:] : duplicateDigests
        guard let control = begin(previous == nil ? "正在比对重复文件" : "正在检查变化的重复文件") else { return }
        pendingAutoRefresh.remove(.duplicates)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    let scan = try StorageScanner.scan(root: root, previous: previous, control: control) { self.progress($0) }
                    let compared = try DuplicateFinder.compare(in: scan, previous: digests, control: control) { self.progress($0) }
                    return SavedDuplicates(scan: scan, groups: compared.groups, digests: compared.digests)
                }.value
                canCancel = false
                let warning = await saveSnapshot(result, key: SavedScans.duplicatesKey)
                duplicateScan = result.scan; duplicateDigests = result.digests
                duplicates = result.groups; duplicateCatalog = result.groups; hasDuplicateScan = true
                duplicateSelection.formIntersection(Set(duplicates.flatMap { $0.files.dropFirst().map(\.id) }))
                waitingForRefresh.remove(.duplicates)
                finish()
                notice = warning ?? (result.scan.skipped.isEmpty ? nil : "有 \(result.scan.skipped.count) 个位置未读取，未参与重复比对。")
            } catch {
                if let duplicateScan { duplicateRoot = duplicateScan.root }
                finish(error)
            }
        }
    }
    func requestTrash(_ items: [CleanupItem]) {
        guard !busy, !items.isEmpty else { return }
        guard !showingSavedResult else {
            notice = "这是上次保存的结果，请先更新本页再清理。"
            return
        }
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
            lastCleaned = report.records.reduce(0) { $0 + $1.bytes }
            if !report.records.isEmpty {
                operation = "正在更新清理结果"; canCancel = false
                await updateResults(moves: report.records.map {
                    FileMove(source: URL(fileURLWithPath: $0.originalPath), destination: URL(fileURLWithPath: $0.trashPath))
                })
            }
            pending = []; loadHistory(); finish()
            let failures = report.failures + (blockedIDs.isEmpty ? [] : ["已跳过 \(blockedIDs.count) 个正在运行的应用 / 关联项目，请退出应用后重新扫描。"])
            notice = "已将 \(report.records.count) 项（\(sizeText(lastCleaned))）移到废纸篓。结果已更新，可继续整理；清空废纸篓后才会释放空间。"
            if !failures.isEmpty { details = failures; showingDetails = true }
        }
    }
    func restore(_ record: TrashRecord) {
        guard let _ = begin("正在恢复文件", cancellable: false) else { return }
        let service = trashService
        Task {
            do {
                try await Task.detached { try service.restore(record) }.value
                operation = "正在更新恢复结果"
                await updateResults(moves: [FileMove(source: URL(fileURLWithPath: record.trashPath), destination: URL(fileURLWithPath: record.originalPath))], restoring: true)
                loadHistory(); finish(); notice = "已恢复到原位置：\(record.originalPath)"
            } catch { finish(error) }
        }
    }
    private func updateResults(moves: [FileMove], restoring: Bool = false) async {
        let previousScan = storage, changes = moves.flatMap { [$0.source, $0.destination] }
        var cleanupInput = cleanup, appInput = apps
        if restoring {
            let ids = Set(cleanupInput.map(\.id))
            cleanupInput += cleanupCatalog.filter { !ids.contains($0.id) && ScanUpdater.intersects($0.url, changes: changes) }
            for template in appCatalog {
                if let index = appInput.firstIndex(where: { $0.id == template.id }) {
                    let current = appInput[index], relatedIDs = Set(current.related.map(\.id))
                    let restored = template.related.filter { !relatedIDs.contains($0.id) && ScanUpdater.intersects($0.url, changes: changes) }
                    appInput[index] = AppFootprint(name: current.name, url: current.url, bundleID: current.bundleID,
                                                  version: current.version, bundle: current.bundle,
                                                  related: current.related + restored, skippedCount: current.skippedCount)
                } else if ScanUpdater.intersects(template.url, changes: changes) { appInput.append(template) }
            }
        }
        let cleanupSnapshot = cleanupInput, appSnapshot = appInput, groups = duplicateCatalog
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let scan = try previousScan.map { scan in
                    guard ScanUpdater.intersects(scan.root, changes: changes) else { return scan }
                    return try ScanUpdater.applying(moves, to: scan)
                }
                var cleaned: [CleanupItem] = []
                for item in cleanupSnapshot { if let value = try ScanUpdater.refresh(item, changes: changes) { cleaned.append(value) } }
                return (scan, cleaned, try ScanUpdater.refreshApps(appSnapshot, changes: changes),
                        try ScanUpdater.refreshDuplicates(groups, changes: changes))
            }.value
            storage = result.0; cleanup = result.1; apps = result.2; duplicates = result.3
            cleanupSelection.formIntersection(Set(cleanup.map(\.id)))
            duplicateSelection.formIntersection(Set(duplicates.flatMap { $0.files.dropFirst().map(\.id) }))
            repairBrowserPath()
            var warnings: [String] = []
            if let scan = storage, ScanUpdater.intersects(scan.root, changes: changes),
               let warning = await saveSnapshot(scan, key: SavedScans.storageKey) { warnings.append(warning) }
            if hasCleanupScan, cleanupSnapshot.contains(where: { ScanUpdater.intersects($0.url, changes: changes) }),
               let warning = await saveSnapshot(SavedCleanup(items: cleanup, skipped: cleanupSkipped, index: cleanupIndex), key: SavedScans.cleanupKey) { warnings.append(warning) }
            if hasAppScan, appSnapshot.contains(where: { app in
                ScanUpdater.intersects(app.url, changes: changes) || app.related.contains { ScanUpdater.intersects($0.url, changes: changes) }
            }), let warning = await saveSnapshot(SavedApps(items: apps, index: appIndex), key: SavedScans.appsKey) { warnings.append(warning) }
            if let scan = duplicateScan, ScanUpdater.intersects(scan.root, changes: changes),
               let warning = await saveSnapshot(SavedDuplicates(scan: scan, groups: duplicates, digests: duplicateDigests), key: SavedScans.duplicatesKey) { warnings.append(warning) }
            if let warning = warnings.first { details = [warning]; showingDetails = true }
        } catch {
            // Keep the last snapshot on a partial refresh error rather than discarding every page.
            details = ["局部更新未完成，已有结果仍保留：\(error.localizedDescription)"]
            showingDetails = true
        }
    }

    private func repairBrowserPath() {
        guard let scan = storage else { return }
        var path = browserPath
        if path.isEmpty || !Paths.isInside(URL(fileURLWithPath: path), root: scan.root) { path = scan.root.path }
        while scan.nodes[path]?.isDirectory != true && path != scan.root.path {
            path = URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        if browserPath != path { browserPath = path }
        if let selected = mapSelectedPath, scan.nodes[selected] == nil { mapSelectedPath = nil }
    }

    func openMapNode(_ node: FileNode) {
        if node.isDirectory { browserPath = node.id; mapSelectedPath = nil }
        else { mapSelectedPath = node.id }
    }
    func mapUp() {
        guard let scan = storage, browserPath != scan.root.path else { return }
        let parent = URL(fileURLWithPath: browserPath).deletingLastPathComponent().path
        if scan.nodes[parent] != nil { browserPath = parent; mapSelectedPath = nil }
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
