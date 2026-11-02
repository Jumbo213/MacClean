import SwiftUI
import MacCleanCore

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<String> private var search = ""
    @ViewState<String?> private var selectedID: String?
    @ViewState<Set<String>> private var relatedSelection: Set<String> = []
    private var selected: AppFootprint? { model.apps.first { $0.id == selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TitleBlock(title: "应用占用，一目了然。", subtitle: "统计应用本体与标识符精确匹配的关联数据，按总占用排序。")
                Spacer(); PrimaryButton(title: "扫描应用", symbol: "magnifyingglass") { model.scanApps() }.disabled(model.busy)
            }
            if model.hasAppScan {
                HStack { Text("\(model.apps.count) 个应用 · 已识别 \(sizeText(model.apps.reduce(0) { $0 + $1.bytes }))").font(.system(size: 12)).foregroundColor(.muted); Spacer(); TextField("搜索应用", text: $search).textFieldStyle(.roundedBorder).frame(width: 200) }
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                                Button { selectedID = app.id; relatedSelection = [] } label: {
                                    HStack(spacing: 12) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 40, height: 40)
                                        VStack(alignment: .leading, spacing: 5) { Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1); Text(app.version).font(.system(size: 10)).foregroundColor(.muted) }
                                        Spacer(); Text(sizeText(app.bytes)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    }.padding(16).background(selectedID == app.id ? Color.tintSurface.opacity(0.7) : Color.white).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 67)
                            }
                        }
                    }.frame(minWidth: 280)
                    Divider()
                    if let app = selected { detail(app).frame(width: 330) }
                    else { VStack(spacing: 15) { IconTile(symbol: "cursorarrow.click", size: 60); Text("选择应用，查看占用详情").font(.system(size: 12)).foregroundColor(.muted) }.frame(width: 330, height: 350) }
                }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
            } else {
                EmptyPanel(symbol: "square.stack.3d.up", title: "认识你的应用空间", subtitle: "扫描 /Applications、~/Applications 与系统应用。关联数据仅统计精确匹配的目录；共享容器与自定义数据目录不会被猜测归属。", action: { model.scanApps() }).disabled(model.busy)
            }
        }.padding(32)
    }
    private func detail(_ app: AppFootprint) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 64, height: 64)
                Text(app.name).font(.system(size: 21, weight: .semibold))
                Text(app.bundleID.isEmpty ? "未声明应用标识符" : app.bundleID).font(.system(size: 10)).foregroundColor(.muted).textSelection(.enabled)
                HStack { Text("应用本体"); Spacer(); Text(sizeText(app.bundle.bytes)).fontWeight(.semibold) }.font(.system(size: 12))
                HStack { Text("关联数据"); Spacer(); Text(sizeText(app.bytes - app.bundle.bytes)).fontWeight(.semibold) }.font(.system(size: 12))
                if app.skippedCount > 0 { Text("\(app.skippedCount) 处未读取，当前统计不完整。").font(.system(size: 10)).foregroundColor(.orange) }
                Divider()
                Text("关联文件 · 可选").font(.system(size: 12, weight: .semibold))
                Text("可能包含设置、文档与登录状态。卸载时默认保留；请仔细确认后再选。").font(.system(size: 10)).foregroundColor(.muted).lineSpacing(4)
                ForEach(app.related) { item in
                    HStack(alignment: .top, spacing: 8) {
                        CheckBox(checked: relatedSelection.contains(item.id)) { if !relatedSelection.insert(item.id).inserted { relatedSelection.remove(item.id) } }
                        VStack(alignment: .leading, spacing: 4) { Text(Paths.short(item.url)).font(.system(size: 10)).lineLimit(3).textSelection(.enabled); Text(sizeText(item.bytes)).font(.system(size: 10)).foregroundColor(.muted) }
                        Spacer(); Button { model.reveal(item.url) } label: { Image(systemName: "arrow.up.forward.square").font(.system(size: 10)) }.buttonStyle(.plain)
                    }
                }
                SecondaryButton(title: "在 Finder 中显示", symbol: "arrow.up.forward.square") { model.reveal(app.url) }
                PrimaryButton(title: "卸载应用…", symbol: "trash") {
                    model.requestTrash([app.bundle] + app.related.filter { relatedSelection.contains($0.id) })
                }.disabled(model.busy || app.url.path.hasPrefix("/System/"))
                Text(app.url.path.hasPrefix("/System/") ? "系统应用受到保护。" : "正在运行的应用会在清理时跳过。").font(.system(size: 10)).foregroundColor(.muted)
            }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
