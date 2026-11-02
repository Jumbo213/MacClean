import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--ui-check"), CommandLine.arguments.count > index + 1 {
            let report = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let model = AppModel.active, let window = NSApp.windows.first(where: { $0.isVisible }) {
                    await UIValidation.run(model: model, window: window, report: report)
                }
                NSApp.terminate(nil)
            }
        }
        // Local render hook for reproducible UI verification. Never changes user files.
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct MacCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.forLaunch()
    var body: some Scene {
        WindowGroup("MacClean") {
            ContentView().environmentObject(model).frame(minWidth: 1080, minHeight: 740)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("选择文件夹…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("扫描存储空间") { model.page = .storage; model.scanStorage() }.keyboardShortcut("r").disabled(model.busy)
            }
        }
    }
}
