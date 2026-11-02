import SwiftUI
import MacCleanCore

struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @ViewState<String> private var search = ""
    @ViewState<Bool> private var largeOnly = false
    @ViewState<Set<String>> private var selected: Set<String> = []
    @ViewState<Bool> private var sortName = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TitleBlock(title: "每一份空间，都有迹可循。", subtitle: "逐层查看文件夹占用，或直接找出大文件。")
                Spacer()
                SecondaryButton(title: "选择文件夹") { model.chooseFolder() }.disabled(model.busy)
                PrimaryButton(title: model.storage == nil ? "开始扫描" : "重新扫描", symbol: "magnifyingglass") { selected = []; model.scanStorage() }.disabled(model.busy)
            }
            HStack {
                Label(Paths.short(model.chosenRoot), systemImage: "folder").font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("用户目录") { model.chosenRoot = FileManager.default.homeDirectoryForCurrentUser; selected = []; model.scanStorage() }.disabled(model.busy)
                Button("整盘分析") { model.chosenRoot = URL(fileURLWithPath: "/"); selected = []; model.scanStorage() }.disabled(model.busy)
            }.foregroundColor(.muted)
            if let scan = model.storage {
                browser(scan)
            } else {
                EmptyPanel(symbol: "internaldrive", title: "从一个文件夹开始", subtitle: "选择用户目录、整个磁盘或任意文件夹。扫描结果包含可读取的文件和隐藏文件；受权限保护的位置会单独提示。", action: { model.scanStorage() }).disabled(model.busy)
            }
        }.padding(32)
    }
    private func browser(_ scan: StorageScan) -> some View {
        let nodes = currentNodes(scan)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { navigateUp(scan) } label: { Image(systemName: "arrow.up") }.disabled(model.browserPath == scan.root.path || largeOnly).buttonStyle(.bordered)
                Text(largeOnly ? "大于 100 MB 的文件 · 当前扫描范围" : Paths.short(URL(fileURLWithPath: model.browserPath))).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Toggle("大文件", isOn: $largeOnly).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).onChange(of: largeOnly) { _ in selected = [] }
                TextField("搜索名称", text: $search).textFieldStyle(.roundedBorder).frame(width: 150)
            }.padding(16)
            if !largeOnly { proportionalBar(scan) }
            HStack {
                Text("名称"); Spacer(); Button(sortName ? "名称排序 ↓" : "占用空间 ↓") { sortName.toggle() }.buttonStyle(.plain)
            }.font(.system(size: 10, weight: .medium)).foregroundColor(.muted).padding(.horizontal, 23).padding(.vertical, 12).background(Color.canvas)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(nodes) { node in fileRow(node, scan: scan); Divider().padding(.leading, 54) }
                    if nodes.isEmpty { Text("这里没有符合条件的项目").font(.system(size: 13)).foregroundColor(.muted).padding(50) }
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(nodes.count) 项 · 扫描共 \(sizeText(scan.total))").font(.system(size: 11, weight: .medium))
                    Text("显示磁盘分配大小；APFS 克隆、快照与可清除空间会影响系统统计。").font(.system(size: 9)).foregroundColor(.muted)
                }
                Spacer()
                if !scan.skipped.isEmpty { Button("\(scan.skipped.count) 处未读取") { model.showDetails(scan.skipped) }.font(.system(size: 11)) }
                SecondaryButton(title: "清理所选 (\(selected.count))", symbol: "trash") {
                    model.requestTrash(nodes.filter { selected.contains($0.id) }.map { model.item(for: $0) })
                }.disabled(selected.isEmpty || model.busy)
            }.padding(15)
        }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
    }
    private func currentNodes(_ scan: StorageScan) -> [FileNode] {
        let all = largeOnly ? scan.files.filter { $0.logicalBytes >= 100_000_000 } : scan.children(of: model.browserPath)
        let filtered = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return filtered.sorted { sortName ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.bytes > $1.bytes }
    }
    private func fileRow(_ node: FileNode, scan: StorageScan) -> some View {
        HStack(spacing: 12) {
            CheckBox(checked: selected.contains(node.id), locked: node.stamp.isSymlink) { if !selected.insert(node.id).inserted { selected.remove(node.id) } }
            IconTile(symbol: node.stamp.isSymlink ? "link" : (node.isDirectory ? "folder" : "doc"), size: 34)
            Button {
                if node.isDirectory { model.browserPath = node.id; selected = []; search = "" }
                else { model.reveal(node.url) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) { Text(node.name).font(.system(size: 12, weight: .medium)); if node.unreadable { Image(systemName: "lock").font(.system(size: 9)).foregroundColor(.muted) } }
                    if largeOnly { Text(Paths.short(node.url.deletingLastPathComponent())).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle) }
                    else if node.isDirectory { Text("\(node.fileCount) 个文件\(node.unreadable ? " · 部分未读取" : "")").font(.system(size: 10)).foregroundColor(.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text(sizeText(node.bytes)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Button { model.reveal(node.url) } label: { Image(systemName: "arrow.up.forward.square").foregroundColor(.muted) }.buttonStyle(.plain).help("在 Finder 中显示")
        }.padding(.horizontal, 18).padding(.vertical, 12).contextMenu {
            Button("在 Finder 中显示") { model.reveal(node.url) }
            Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.url.path, forType: .string) }
        }
    }
    private func proportionalBar(_ scan: StorageScan) -> some View {
        let children = Array(scan.children(of: model.browserPath).prefix(7))
        let total = max(1, scan.nodes[model.browserPath]?.bytes ?? 1)
        let colors: [Color] = [.accent, Color(red: 0.30, green: 0.64, blue: 0.54), Color(red: 0.54, green: 0.73, blue: 0.62), Color(red: 0.76, green: 0.80, blue: 0.57), Color(red: 0.82, green: 0.68, blue: 0.46), Color(red: 0.65, green: 0.73, blue: 0.77), Color.line]
        return GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, node in
                    RoundedRectangle(cornerRadius: 3).fill(colors[index]).frame(width: max(0, (proxy.size.width - 14) * CGFloat(Double(node.bytes) / Double(total))))
                        .help("\(node.name) · \(sizeText(node.bytes))")
                        .onTapGesture { if node.isDirectory { model.browserPath = node.id; selected = [] } }
                }
            }
        }.frame(height: 14).padding(.horizontal, 18).padding(.bottom, 13)
    }
    private func navigateUp(_ scan: StorageScan) {
        let parent = URL(fileURLWithPath: model.browserPath).deletingLastPathComponent()
        if Paths.isInside(parent, root: scan.root) { model.browserPath = parent.path; selected = []; search = "" }
    }
}
