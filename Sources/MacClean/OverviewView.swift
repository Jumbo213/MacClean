import SwiftUI
import MacCleanCore

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    private var currentPath: String { model.storage?.nodes[model.browserPath] != nil ? model.browserPath : (model.storage?.root.path ?? "") }
    @ViewState<[FileNode]> private var bigFiles: [FileNode] = []
    private var mapRevision: String { "\(model.storage?.completed.timeIntervalSince1970 ?? 0):\(currentPath)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    TitleBlock(title: "空间去向，一眼看清。", subtitle: "按占用比例绘制圆环，点击文件夹逐层探索。")
                    Spacer()
                    PrimaryButton(title: model.storage == nil ? "分析空间" : "刷新分析", symbol: "arrow.clockwise") { model.scanStorage() }.disabled(model.busy)
                }
                HStack(spacing: 14) {
                    metric("已使用", bytes: model.usedCapacity, symbol: "internaldrive", detail: "磁盘总计 \(sizeText(model.totalCapacity))")
                    metric("可用空间", bytes: model.availableCapacity, symbol: "externaldrive", detail: "来自 macOS 实时统计")
                    metric("建议清理", bytes: model.recommendedBytes, symbol: "sparkles", detail: model.hasCleanupScan ? "缓存与日志 · 结果持续保留" : "扫描后显示清理建议")
                }
                Card {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("存储空间分布").font(.system(size: 16, weight: .semibold))
                                Text(model.storage.map { $0.root == FileManager.default.homeDirectoryForCurrentUser ? "扫描范围：用户目录" : "扫描范围：\(Paths.short($0.root))" } ?? "等待首次分析")
                                    .font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            SecondaryButton(title: "选择目录") { model.chooseFolderForMap() }.disabled(model.busy)
                            SecondaryButton(title: "整盘分析", symbol: "internaldrive") { model.chosenRoot = URL(fileURLWithPath: "/"); model.scanStorage() }.disabled(model.busy)
                        }
                        if let scan = model.storage {
                            HStack(spacing: 8) {
                                Button { model.mapUp() } label: { Image(systemName: "arrow.up").frame(width: 24, height: 23).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(currentPath == scan.root.path)
                                Button("扫描根目录") { model.browserPath = scan.root.path; model.mapSelectedPath = nil }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.accent)
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(.muted)
                                Text(scan.nodes[currentPath]?.name ?? "当前目录").font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text("\(scan.nodes[currentPath]?.fileCount ?? 0) 个文件").font(.system(size: 10)).foregroundColor(.muted)
                            }
                            if scan.nodes[currentPath]?.bytes ?? 0 > 0 { DiskMapView(scan: scan, path: currentPath) }
                            else { Text("当前目录没有可读取的占用数据").font(.system(size: 13)).foregroundColor(.muted).frame(maxWidth: .infinity).frame(height: 240) }
                            if let id = model.mapSelectedPath, let file = scan.nodes[id] {
                                selectedFile(file)
                            }
                            if !scan.skipped.isEmpty {
                                Button("\(scan.skipped.count) 个位置未读取，查看详情") { model.showDetails(scan.skipped) }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.muted)
                            }
                        } else {
                            HStack(spacing: 35) {
                                ZStack { Circle().stroke(Color.line, lineWidth: 45); Circle().stroke(Color.canvas, lineWidth: 24).padding(39); Image(systemName: "internaldrive").font(.system(size: 35, weight: .light)).foregroundColor(.muted) }.frame(width: 220, height: 220).padding(20)
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(model.busy ? "正在绘制你的空间地图" : "开始绘制空间地图").font(.system(size: 18, weight: .semibold))
                                    Text("分析完成后，大文件与文件夹会显示为不同颜色的扇区。占用越大，扇区越宽。").font(.system(size: 12)).foregroundColor(.muted).lineSpacing(5)
                                    if !model.busy { PrimaryButton(title: "分析用户目录", symbol: "magnifyingglass") { model.scanStorage() } }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if !bigFiles.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack { Text("最大的文件").font(.system(size: 15, weight: .semibold)); Spacer(); Text("当前浏览范围 · TOP 5").font(.system(size: 9, weight: .medium)).tracking(0.7).foregroundColor(.muted) }
                            ForEach(Array(bigFiles.enumerated()), id: \.element.id) { index, file in
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.muted).frame(width: 22)
                                    IconTile(symbol: "doc", color: AppTheme.chart[index], size: 32)
                                    Button { model.browserPath = file.url.deletingLastPathComponent().path; model.mapSelectedPath = file.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Text(Paths.short(file.url.deletingLastPathComponent())).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Text(sizeText(file.bytes)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    Button { model.reveal(file.url) } label: { Image(systemName: "arrow.up.forward.square").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundColor(.muted).help("在 Finder 中显示")
                                    Button { model.requestTrash([model.item(for: file)]) } label: { Image(systemName: "trash").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundColor(.muted).disabled(model.busy).help("预览清理")
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                }
                HStack(spacing: 15) {
                    IconTile(symbol: "sparkles")
                    VStack(alignment: .leading, spacing: 6) { Text("整理之后，继续探索。").font(.system(size: 14, weight: .semibold)); Text("清理后自动更新占用与剩余项目，无需从头扫描。").font(.system(size: 11)).foregroundColor(.muted) }
                    Spacer()
                    SecondaryButton(title: model.hasCleanupScan ? "查看清理建议" : "扫描垃圾", symbol: "sparkles") { model.page = .cleanup; if !model.hasCleanupScan { model.scanCleanup() } }.disabled(model.busy)
                }.padding(19).background(Color.tintSurface).clipShape(RoundedRectangle(cornerRadius: 15))
            }.padding(28)
        }.onAppear {
            if !model.hasAttemptedStorageScan && !model.busy { model.scanStorage() }
        }.task(id: mapRevision) {
            guard let scan = model.storage else { bigFiles = []; return }
            let root = URL(fileURLWithPath: currentPath)
            let files = await Task.detached(priority: .utility) {
                Array(scan.files.filter { $0.bytes > 0 && Paths.isInside($0.url, root: root) }.sorted { $0.bytes > $1.bytes }.prefix(5))
            }.value
            if !Task.isCancelled { bigFiles = files }
        }
    }
    private func metric(_ title: String, bytes: Int64, symbol: String, detail: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, size: 38)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 10)).foregroundColor(.muted); Text(sizeText(bytes)).font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.7).monospacedDigit(); Text(detail).font(.system(size: 9)).foregroundColor(.muted).lineLimit(1) }
            Spacer(minLength: 0)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 15))
    }
    private func selectedFile(_ file: FileNode) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "doc", size: 32)
            VStack(alignment: .leading, spacing: 4) { Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1); Text(Paths.short(file.url)).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle) }
            Spacer(); Text(sizeText(file.bytes)).font(.system(size: 12, weight: .semibold))
            Button("显示") { model.reveal(file.url) }
            Button("清理…") { model.requestTrash([model.item(for: file)]) }.disabled(model.busy)
        }.padding(12).background(Color.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
