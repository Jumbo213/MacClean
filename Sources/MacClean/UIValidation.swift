import AppKit
import MacCleanCore

/// A local integration harness. Only creates, trashes and restores its own UUID-named fixtures.
@MainActor enum UIValidation {
    static func run(model: AppModel, window: NSWindow, report: URL) async {
        var passed: [String] = [], failures: [String] = [], debug: [String] = []
        func check(_ value: Bool, _ name: String) { if value { passed.append(name) } else { failures.append(name) } }
        let fm = FileManager.default, fixture = model.trashService.historyURL.deletingLastPathComponent()
        guard fixture.lastPathComponent.hasPrefix("MacClean-ui-fixture-") else { return }
        do {
            try fm.createDirectory(at: fixture.appendingPathComponent("Caches"), withIntermediateDirectories: true)
            try fm.createDirectory(at: fixture.appendingPathComponent("Copies"), withIntermediateDirectories: true)
            let a = fixture.appendingPathComponent("Caches/first.cache"), b = fixture.appendingPathComponent("Caches/second.cache")
            try Data(repeating: 7, count: 16384).write(to: a)
            try Data(repeating: 8, count: 32768).write(to: b)
            let data = Data(repeating: 42, count: 1_100_000)
            for name in ["one", "two", "three"] { try data.write(to: fixture.appendingPathComponent("Copies/" + name)) }
            model.chosenRoot = fixture; model.scanStorage(); try await waitUntilIdle(model)
            model.duplicateRoot = fixture.appendingPathComponent("Copies"); model.scanDuplicates(); try await waitUntilIdle(model)
            check(model.storage != nil && model.duplicates.count == 1, "Initial fixture scans complete")
            // Click the trailing blank area of every navigation row through real AppKit mouse events.
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            var calibratedOffset: CGFloat?
            for page in [Page.storage, .apps, .cleanup, .duplicates, .history, .settings, .overview] {
                model.page = page == .overview ? .settings : .overview
                try await Task.sleep(nanoseconds: 100_000_000)
                guard let rect = model.navigationFrames[page.rawValue], let view = window.contentView else {
                    failures.append("Navigation frame: " + page.rawValue); continue
                }
                var clicked = false
                for offset in calibratedOffset.map({ [$0] }) ?? [0, 28, -28] {
                    let y = view.isFlipped ? rect.midY + offset : view.bounds.height - rect.midY - offset
                    let location = view.convert(NSPoint(x: rect.maxX - 11, y: y), to: nil)
                    if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                       let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) {
                        NSApp.postEvent(down, atStart: false); NSApp.postEvent(up, atStart: false)
                        try await Task.sleep(nanoseconds: 150_000_000)
                        debug.append("\(page.rawValue) frame=\(rect) offset=\(offset) flipped=\(view.isFlipped) result=\(model.page.rawValue)")
                        if model.page == page { calibratedOffset = offset; clicked = true; break }
                    }
                }
                check(clicked, "Blank-area sidebar click: " + page.rawValue)
            }
            model.page = .overview
            try await Task.sleep(nanoseconds: 200_000_000)
            if let rect = model.navigationFrames["disk-map"], let view = window.contentView {
                let x = rect.minX + 146 + 88 * sin(Double.pi / 4)
                let topY = rect.minY + 146 - 88 * cos(Double.pi / 4) + (calibratedOffset ?? 0)
                let location = view.convert(NSPoint(x: x, y: view.isFlipped ? topY : view.bounds.height - topY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) { NSApp.postEvent(event, atStart: false) }
                }
                try await Task.sleep(nanoseconds: 150_000_000)
                debug.append("Map frame=\(rect) location=\(location) resultPage=\(model.page.rawValue) browser=\(model.browserPath) selected=\(model.mapSelectedPath ?? "nil")")
                check(model.browserPath == fixture.appendingPathComponent("Copies").path, "Ring sector click opens directory")
            } else { failures.append("Disk map frame missing") }
            guard let scan = model.storage, let first = scan.nodes[a.path], let second = scan.nodes[b.path] else { throw MCError.invalid("Missing fixture snapshot") }
            model.page = .cleanup
            model.cleanup = [model.item(for: first), model.item(for: second)]
            model.cleanupSelection = [a.path, b.path]; model.hasCleanupScan = true; model.hasAppScan = true
            model.browserPath = a.deletingLastPathComponent().path
            model.requestTrash([model.item(for: first)]); model.confirmTrash(); try await waitUntilIdle(model)
            check(model.storage != nil, "Storage snapshot retained after first cleanup")
            check(model.browserPath == a.deletingLastPathComponent().path, "Browser position retained")
            check(model.cleanup.count == 1 && model.cleanup.first?.id == b.path, "Remaining cleanup item retained")
            check(model.cleanupSelection == [b.path], "Remaining selection retained")
            check(model.hasAppScan && model.hasDuplicateScan && model.duplicates.count == 1, "Other scanned pages retained")
            guard let remaining = model.cleanup.first else { throw MCError.invalid("Remaining cleanup item missing") }
            model.requestTrash([remaining]); model.confirmTrash(); try await waitUntilIdle(model)
            check(model.cleanup.isEmpty && model.hasCleanupScan, "Second cleanup without a rescan")
            check(model.storage?.nodes[b.path] == nil && model.storage?.nodes[a.path] == nil, "Both removals reflected in cached tree")
            check(model.history.count == 2 && !model.showingDetails, "Both fixture files cleaned without errors")
            let records = model.history
            for record in records { model.restore(record); try await waitUntilIdle(model) }
            check(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path), "Fixture restore succeeds")
            check(model.storage?.nodes[a.path] != nil && model.storage?.nodes[b.path] != nil, "Restored files reappear without rescan")
        } catch { failures.append(error.localizedDescription) }
        // Recover only records belonging to this fixture before removing the scratch folder.
        for record in (try? model.trashService.load()) ?? [] where record.restoredAt == nil {
            try? model.trashService.restore(record)
        }
        try? fm.removeItem(at: fixture)
        let result: [String: Any] = ["passed": passed, "failures": failures, "success": failures.isEmpty, "clickDiagnostics": debug]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: report) }
    }
    private static func waitUntilIdle(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(40)
        while model.busy {
            guard Date() < deadline else { throw MCError.invalid("UI validation operation timed out") }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        try await Task.sleep(nanoseconds: 80_000_000)
    }
}
