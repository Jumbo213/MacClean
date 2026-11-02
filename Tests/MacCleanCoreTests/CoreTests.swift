import Foundation
import MacCleanCore

final class CoreTests: TestCase {
    var root: URL!
    let fm = FileManager.default
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/fixtures-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? fm.removeItem(at: root) } }
    @discardableResult func file(_ relative: String, data: Data = Data(repeating: 42, count: 8192), age: Double = 0) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if age > 0 { try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age * 86400)], ofItemAtPath: url.path) }
        return url
    }
    func item(_ url: URL) throws -> CleanupItem {
        CleanupItem(url: url, bytes: 8192, category: "测试", reason: "测试", recommended: false, stamp: try FileStamp(url: url))
    }
    func testNestedTotalsAndHiddenFiles() throws {
        try file("folder/a"); try file("folder/b", data: Data(repeating: 1, count: 16000)); try file(".hidden")
        let scan = try StorageScanner.scan(root: root)
        XCTAssertEqual(scan.nodes[root.path]?.fileCount, 3)
        XCTAssertEqual(scan.nodes[root.appendingPathComponent("folder").path]?.logicalBytes, 24192)
        XCTAssertNotNil(scan.nodes[root.appendingPathComponent(".hidden").path])
        XCTAssertGreaterThan(scan.total, 0)
        XCTAssertEqual(scan.children(of: root.path).count, 2)
    }
    func testSymlinksAreNotFollowed() throws {
        try file("real/a")
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("real"))
        let scan = try StorageScanner.scan(root: root)
        XCTAssertEqual(scan.nodes[link.path]?.bytes, 0)
        XCTAssertNil(scan.nodes[link.appendingPathComponent("a").path])
        XCTAssertThrowsError(try StorageScanner.scan(root: link))
        XCTAssertThrowsError(try SafetyPolicy.validate(item(link)))
    }
    func testHardLinksAreCountedOnce() throws {
        let a = try file("a"), b = root.appendingPathComponent("b")
        try fm.linkItem(at: a, to: b)
        let scan = try StorageScanner.scan(root: root)
        let bytes = [scan.nodes[a.path]!.bytes, scan.nodes[b.path]!.bytes]
        XCTAssertEqual(bytes.filter { $0 == 0 }.count, 1)
    }
    func testCancellation() throws {
        let control = ScanControl(); control.cancel()
        XCTAssertThrowsError(try StorageScanner.scan(root: root, control: control)) { XCTAssertTrue($0 is MCError) }
    }
    func testMissingRootFails() { XCTAssertThrowsError(try StorageScanner.scan(root: root.appendingPathComponent("missing"))) }
    func testDuplicateContentRatherThanName() throws {
        let data = Data(repeating: 0x64, count: 1_100_000)
        let a = try file("a.txt", data: data)
        let b = try file("nested/renamed.bin", data: data, age: 1)
        try file("other/a.txt", data: Data(repeating: 0x65, count: data.count))
        let groups = try DuplicateFinder.find(in: StorageScanner.scan(root: root))
        XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].files.first?.url, a)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), Set([a, b]))
    }
    func testDuplicateChangedFileIsExcluded() throws {
        let data = Data(repeating: 7, count: 1_100_000)
        try file("a", data: data); let b = try file("b", data: data)
        let scan = try StorageScanner.scan(root: root)
        try Data(repeating: 8, count: data.count).write(to: b)
        try XCTAssertEqual(try DuplicateFinder.find(in: scan).count, 0)
    }
    func testSHA256KnownVector() throws {
        let url = try file("abc", data: Data("abc".utf8))
        try XCTAssertEqual(try DuplicateFinder.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testCleanupAgeAndManualCategories() throws {
        let home = root.appendingPathComponent("Home")
        try file("Home/Library/Caches/old.cache", age: 20)
        try file("Home/Library/Caches/new.cache", age: 1)
        try file("Home/Library/Logs/old.log", age: 20)
        try file("Home/Library/Developer/Xcode/DerivedData/build", age: 40)
        try file("Home/Downloads/installer.dmg", age: 40)
        try file("Home/Downloads/personal.pdf", age: 100)
        let result = try CleanupScanner.scan(home: home)
        XCTAssertEqual(result.items.count, 5)
        XCTAssertEqual(Set(result.items.filter(\.recommended).map(\.category)), Set(["应用缓存", "旧日志"]))
        XCTAssertFalse(result.items.contains { $0.url.lastPathComponent == "new.cache" })
    }
    func testRecentChildPreventsOldCacheRecommendation() throws {
        try file("Home/Library/Caches/cache/new", age: 1)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86400)], ofItemAtPath: root.appendingPathComponent("Home/Library/Caches/cache").path)
        try XCTAssertTrue(try CleanupScanner.scan(home: root.appendingPathComponent("Home")).items.isEmpty)
    }
    func testRunningAppCacheIsSkipped() throws {
        try file("Home/Library/Caches/com.example.running", age: 20)
        let result = try CleanupScanner.scan(home: root.appendingPathComponent("Home"), runningBundleIDs: ["com.example.running"])
        XCTAssertTrue(result.items.isEmpty)
    }
    func testProtectedPaths() throws {
        for path in ["/", "/System", "/Applications", "/Users", "/Library", fm.homeDirectoryForCurrentUser.path] {
            let url = URL(fileURLWithPath: path)
            if let item = try? item(url) { XCTAssertThrowsError(try SafetyPolicy.validate(item), path) }
        }
    }
    func testChangedIdentityAndContentAreRejected() throws {
        let url = try file("a"), captured = try item(url)
        try Data("new contents".utf8).write(to: url)
        XCTAssertThrowsError(try SafetyPolicy.validate(captured))
        let current = try item(url)
        try fm.removeItem(at: url); try Data("replacement".utf8).write(to: url)
        XCTAssertThrowsError(try SafetyPolicy.validate(current))
    }
    func testSymlinkParentIsRejected() throws {
        try file("real/a")
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("real"))
        XCTAssertThrowsError(try SafetyPolicy.validate(item(link.appendingPathComponent("a"))))
    }
    func testPathBoundariesAndOverlaps() throws {
        XCTAssertFalse(Paths.isInside(URL(fileURLWithPath: "/Users/bob"), root: URL(fileURLWithPath: "/Users/bo")))
        let child = try file("dir/a"), parent = root.appendingPathComponent("dir")
        let reduced = SafetyPolicy.removingOverlaps([try item(child), try item(parent), try item(parent)])
        XCTAssertEqual(reduced.count, 1); XCTAssertEqual(reduced.first?.url, parent)
    }
    func testAppFootprintExactMatches() throws {
        let app = root.appendingPathComponent("Applications/Test.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.macclean.test", "CFBundleName": "Test", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try file("Home/Library/Caches/com.macclean.test/cache")
        try file("Home/Library/Caches/com.macclean.test.other/cache")
        let apps = try AppScanner.scan(home: root.appendingPathComponent("Home"), directories: [root.appendingPathComponent("Applications")])
        XCTAssertEqual(apps.count, 1); XCTAssertEqual(apps.first?.related.count, 1)
        XCTAssertEqual(apps.first?.bundleID, "com.macclean.test")
    }
    func testCorruptHistoryBlocksCleanup() throws {
        let history = try file("history.json", data: Data("broken".utf8)), target = try file("target")
        let report = TrashService(historyURL: history).trash([try item(target)])
        XCTAssertTrue(report.records.isEmpty); XCTAssertFalse(report.failures.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: target.path))
    }
    func testTrashAndRestoreIntegration() throws {
        guard ProcessInfo.processInfo.environment["MC_INTEGRATION_TRASH"] == "1" else { throw XCTSkip("设置 MC_INTEGRATION_TRASH=1 测试真实废纸篓往返，仅操作临时夹具") }
        let target = try file("MacClean-test-" + UUID().uuidString + ".txt", data: Data("fixture".utf8))
        let service = TrashService(historyURL: root.appendingPathComponent("history.json"))
        let report = service.trash([try item(target)])
        XCTAssertTrue(report.failures.isEmpty, report.failures.joined(separator: ";"))
        let record = try XCTUnwrap(report.records.first)
        defer { if fm.fileExists(atPath: record.trashPath) { try? fm.moveItem(atPath: record.trashPath, toPath: target.path) } }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
        XCTAssertTrue(fm.fileExists(atPath: record.trashPath))
        // Refuse to overwrite a new file at the original location.
        try Data("replacement".utf8).write(to: target)
        XCTAssertThrowsError(try service.restore(record))
        try fm.removeItem(at: target)
        try service.restore(record)
        try XCTAssertEqual(try String(contentsOf: target), "fixture")
        XCTAssertNotNil(try service.load().first?.restoredAt)
    }
    func testChangedDirectoryDescendantsAreRejected() throws {
        let child = try file("dir/a"), directory = root.appendingPathComponent("dir")
        let snapshot = try StorageScanner.scan(root: directory)
        let captured = CleanupItem(url: directory, bytes: snapshot.total, category: "测试", reason: "测试", recommended: false, stamp: try FileStamp(url: directory), treeFingerprint: snapshot.fingerprint())
        try SafetyPolicy.validate(captured)
        try Data("changed child".utf8).write(to: child)
        XCTAssertThrowsError(try SafetyPolicy.validate(captured))
    }
    func testDuplicateRetainedCopyMustRemainValid() throws {
        let data = Data(repeating: 7, count: 1_100_000)
        let kept = try file("kept", data: data), extra = try file("extra", data: data)
        let proof = DuplicateProof(retainedURL: kept, retainedStamp: try FileStamp(url: kept), digest: try DuplicateFinder.sha256(kept))
        let duplicate = CleanupItem(url: extra, bytes: Int64(data.count), category: "重复", reason: "测试", recommended: false, stamp: try FileStamp(url: extra), duplicateProof: proof)
        try SafetyPolicy.validate(duplicate)
        try Data("changed retained copy".utf8).write(to: kept)
        XCTAssertThrowsError(try SafetyPolicy.validate(duplicate))
        try fm.removeItem(at: kept)
        XCTAssertThrowsError(try SafetyPolicy.validate(duplicate))
    }
    func testCancelledTrashPreservesFiles() throws {
        let target = try file("target"), control = ScanControl(); control.cancel()
        let report = TrashService(historyURL: root.appendingPathComponent("history.json")).trash([try item(target)], control: control)
        XCTAssertTrue(report.records.isEmpty); XCTAssertFalse(report.failures.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: target.path))
    }

}
