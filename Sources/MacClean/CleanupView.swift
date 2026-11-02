import SwiftUI
import MacCleanCore

struct CleanupView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<String> private var category = "全部"
    private var items: [CleanupItem] { model.visibleCleanup.filter { category == "全部" || $0.category == category } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TitleBlock(title: "清理冗余，留住重要。", subtitle: "仅推荐清理 14 天未修改的缓存与日志，其他项目由你决定。")
                Spacer(); PrimaryButton(title: "扫描垃圾", symbol: "sparkles") { model.scanCleanup() }.disabled(model.busy)
            }
            if model.hasCleanupScan {
                HStack(spacing: 15) {
                    metric("发现可整理", value: sizeText(model.visibleCleanup.reduce(0) { $0 + $1.bytes }), symbol: "tray.full")
                    metric("建议清理", value: sizeText(model.recommendedBytes), symbol: "checkmark.shield")
                    metric("已选项目", value: "\(model.cleanupSelection.intersection(Set(model.visibleCleanup.map(\.id))).count) 项", symbol: "checkmark.circle")
                }
                HStack {
                    Picker("类别", selection: $category) {
                        ForEach(["全部"] + Array(Set(model.visibleCleanup.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 145)
                    Spacer()
                    Button("选择建议项") { model.cleanupSelection = Set(model.visibleCleanup.filter(\.recommended).map(\.id)) }
                    Button("取消全选") { model.cleanupSelection = [] }
                }.font(.system(size: 11))
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                DataRow(item: item, checked: model.cleanupSelection.contains(item.id)) { if !model.cleanupSelection.insert(item.id).inserted { model.cleanupSelection.remove(item.id) } }
                                    .contextMenu { Button("以后忽略这个项目") { model.ignore(item.id) }; Button("在 Finder 中显示") { model.reveal(item.url) } }
                                Divider().padding(.leading, 54)
                            }
                            if items.isEmpty { VStack(spacing: 12) { Image(systemName: "checkmark.seal").font(.system(size: 36, weight: .light)).foregroundColor(.accent); Text("当前范围没有可整理的旧文件").font(.system(size: 14)); Text("新缓存会保留；完整磁盘访问权限可提高扫描覆盖率。").font(.system(size: 11)).foregroundColor(.muted) }.padding(50) }
                        }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("已选 \(sizeText(model.cleanupSelectedBytes))").font(.system(size: 14, weight: .semibold))
                            Text("建议先退出相关应用。所有项目都会先移到废纸篓。").font(.system(size: 10)).foregroundColor(.muted)
                        }
                        Spacer()
                        if !model.cleanupSkipped.isEmpty { Button("扫描详情") { model.showDetails(model.cleanupSkipped) }.font(.system(size: 11)) }
                        PrimaryButton(title: "一键清理所选", symbol: "trash") {
                            model.requestTrash(model.visibleCleanup.filter { model.cleanupSelection.contains($0.id) })
                        }.disabled(model.cleanupSelection.isEmpty || model.busy)
                    }.padding(17)
                }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
            } else {
                EmptyPanel(symbol: "sparkles", title: "让旧文件，有序退场", subtitle: "扫描应用缓存、旧日志、Xcode 构建缓存、旧安装包及旧下载。个人下载与开发缓存默认不勾选；不会清理浏览记录、密码或应用文档。", action: { model.scanCleanup() }).disabled(model.busy)
            }
        }.padding(32)
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        Card { HStack(spacing: 13) { IconTile(symbol: symbol); VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 10)).foregroundColor(.muted); Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit() } } }
    }
}
