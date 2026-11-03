import SwiftUI
import MacCleanCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TitleBlock(title: "每一次清理，都有记录。", subtitle: "未清空废纸篓的文件可恢复到原位置，同名文件不会被覆盖。")
                Spacer(); SecondaryButton(title: "打开废纸篓", symbol: "trash") { model.openTrash() }
            }
            if model.history.isEmpty {
                EmptyPanel(symbol: "clock.arrow.circlepath", title: "还没有清理记录", subtitle: "通过 MacClean 移到废纸篓的项目会显示在这里。记录仅保存在你的 Mac 上。", button: "去整理空间", action: { model.page = .cleanup })
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.history) { record in
                            HStack(spacing: 13) {
                                IconTile(symbol: record.restoredAt == nil ? "trash" : "arrow.uturn.backward")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: record.originalPath).lastPathComponent).font(.system(size: 13, weight: .medium))
                                    Text(Paths.short(URL(fileURLWithPath: record.originalPath))).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle)
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundColor(.muted)
                                }
                                Spacer(); Text(sizeText(record.bytes)).font(.system(size: 12)).monospacedDigit()
                                if record.restoredAt != nil { Text("已恢复").font(.system(size: 11)).foregroundColor(.accent) }
                                else if FileManager.default.fileExists(atPath: record.trashPath) {
                                    Button("恢复") { model.restore(record) }.buttonStyle(.bordered).disabled(model.busy)
                                } else { Text("已移走 / 已清空").font(.system(size: 10)).foregroundColor(.muted) }
                            }.padding(18)
                            Divider().padding(.leading, 72)
                        }
                    }
                }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
            }
        }.padding(32).onAppear { model.loadHistory() }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TitleBlock(title: "简单，也保持分寸。", subtitle: "管理扫描权限与忽略项目。MacClean 不需要管理员密码。")
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("完整磁盘访问权限", systemImage: "lock.shield").font(.system(size: 15, weight: .semibold))
                        Text("macOS 可能限制桌面、文稿、下载及部分应用数据的读取。你可以在系统设置中添加 MacClean，并重新打开应用。未授权的位置会在扫描结果中标明，不会被视为 0 字节。").font(.system(size: 12)).foregroundColor(.muted).lineSpacing(5)
                        SecondaryButton(title: "打开系统隐私设置", symbol: "gearshape") { model.openPrivacy() }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("清理忽略列表", systemImage: "eye.slash").font(.system(size: 15, weight: .semibold))
                        Text("在垃圾清理列表中右键项目，选择「以后忽略这个项目」。仅影响垃圾清理建议。").font(.system(size: 12)).foregroundColor(.muted)
                        if model.ignoredPaths.isEmpty { Text("暂时没有忽略的项目").font(.system(size: 11)).foregroundColor(.muted).padding(.vertical, 5) }
                        ForEach(Array(model.ignoredPaths).sorted(), id: \.self) { path in
                            HStack { Text(Paths.short(URL(fileURLWithPath: path))).font(.system(size: 11)).textSelection(.enabled); Spacer(); Button("移除") { model.unignore(path) }.font(.system(size: 11)) }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { TrashMark(); VStack(alignment: .leading, spacing: 5) { Text("MacClean \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.1")").font(.system(size: 16, weight: .semibold)); Text("原生 SwiftUI · MIT 开源协议").font(.system(size: 11)).foregroundColor(.muted) } }
                        Text("离线扫描，不收集文件内容、不发送遥测。不会自动执行清理、永久删除文件、清空废纸篓或修改系统快照。文件大小受权限、硬链接、APFS 克隆和云文件影响，目录合计不等于精确可释放空间。").font(.system(size: 12)).foregroundColor(.muted).lineSpacing(5)
                        Text("应用关联数据仅按 Bundle ID 精确匹配，不能代表完整归属；共享数据与自定义目录可能未包含。").font(.system(size: 11)).foregroundColor(.muted).lineSpacing(4)
                    }
                }
            }.padding(32)
        }
    }
}
