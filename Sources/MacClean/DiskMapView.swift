import SwiftUI
import MacCleanCore

struct DiskMapSlice: Identifiable {
    let id: String
    let node: FileNode?
    let name: String
    let bytes: Int64
    let start: Double
    let end: Double
    let color: Color
    var isOther: Bool { node == nil }
}

struct RingSector: Shape {
    let start: Double
    let end: Double
    let inner: CGFloat
    let outer: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let gap = min(0.006, max(0, (end - start) / 5))
        let from = (start + gap) * 360 - 90, to = (end - gap) * 360 - 90
        guard to > from else { return Path() }
        var path = Path()
        path.addArc(center: center, radius: radius * outer, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        path.addArc(center: center, radius: radius * inner, startAngle: .degrees(to), endAngle: .degrees(from), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct DiskMapView: View {
    @EnvironmentObject var model: AppModel
    let scan: StorageScan
    let path: String
    @ViewState<String?> private var hoveredID: String?
    private var total: Int64 { max(1, scan.nodes[path]?.bytes ?? 0) }
    private var slices: [DiskMapSlice] {
        let nodes = scan.children(of: path).filter { $0.bytes > 0 }
        var values: [DiskMapSlice] = [], cursor = 0.0
        for (index, node) in nodes.prefix(7).enumerated() {
            let end = min(1, cursor + Double(node.bytes) / Double(total))
            values.append(DiskMapSlice(id: node.id, node: node, name: node.name, bytes: node.bytes, start: cursor, end: end, color: AppTheme.chart[index]))
            cursor = end
        }
        let other = max(0, total - nodes.prefix(7).reduce(0) { $0 + $1.bytes })
        if other > 0 { values.append(DiskMapSlice(id: "other", node: nil, name: "其他项目", bytes: other, start: cursor, end: 1, color: AppTheme.chart[7])) }
        return values
    }
    private var outerSlices: [DiskMapSlice] {
        var result: [DiskMapSlice] = []
        for parent in slices {
            guard let node = parent.node, node.isDirectory else {
                result.append(parent); continue
            }
            var cursor = parent.start
            let children = scan.children(of: node.id).filter { $0.bytes > 0 }
            for (index, child) in children.prefix(5).enumerated() {
                let end = min(parent.end, cursor + Double(child.bytes) / Double(total))
                result.append(DiskMapSlice(id: child.id, node: child, name: child.name, bytes: child.bytes,
                                           start: cursor, end: end, color: parent.color.opacity(0.58 + Double(index % 3) * 0.13)))
                cursor = end
            }
            if parent.end - cursor > 0.0001 {
                result.append(DiskMapSlice(id: "other:" + parent.id, node: node, name: node.name + " / 其他", bytes: Int64((parent.end - cursor) * Double(total)), start: cursor, end: parent.end, color: parent.color.opacity(0.45)))
            }
        }
        return result
    }
    private var focused: DiskMapSlice? {
        (slices + outerSlices).first { $0.id == (hoveredID ?? model.mapSelectedPath) }
    }
    var body: some View {
        HStack(spacing: 32) {
            ZStack {
                Circle().stroke(Color.canvas, lineWidth: 1).padding(1)
                ForEach(slices) { slice in sector(slice, inner: 0.49, outer: 0.73) }
                ForEach(outerSlices) { slice in sector(slice, inner: 0.76, outer: 0.98) }
                VStack(spacing: 7) {
                    Text(focused?.name ?? "当前占用").font(.system(size: 11, weight: .medium)).foregroundColor(.muted).lineLimit(2).multilineTextAlignment(.center)
                    Text(sizeText(focused?.bytes ?? (scan.nodes[path]?.bytes ?? 0))).font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Text(focused.map { String(format: "%.1f%%", Double($0.bytes) / Double(total) * 100) } ?? "点击扇区展开")
                        .font(.system(size: 10)).foregroundColor(.muted)
                }.frame(width: 126).allowsHitTesting(false)
            }.frame(width: 292, height: 292)
                .contentShape(Circle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoveredID = slice(at: location)?.id
                    case .ended: hoveredID = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard abs(value.translation.width) < 8, abs(value.translation.height) < 8 else { return }
                    if let hit = slice(at: value.location) { activate(hit) }
                })
                .help(focused.map { "\($0.name) · \(sizeText($0.bytes))" } ?? "点击文件夹扇区展开，或使用右侧列表")
                .accessibilityLabel("磁盘占用环形图，可使用右侧列表选择项目")
                .onChange(of: path) { _ in hoveredID = nil }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("主要占用").font(.system(size: 12, weight: .semibold)); Spacer(); Text("大小 / 占比").font(.system(size: 10)).foregroundColor(.muted) }.padding(.bottom, 3)
                ForEach(slices) { slice in
                    Button { activate(slice) } label: {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 9, height: 9)
                            Text(slice.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 5)
                            Text(sizeText(slice.bytes)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            Text(String(format: "%.0f%%", Double(slice.bytes) / Double(total) * 100)).font(.system(size: 10)).monospacedDigit().foregroundColor(.muted).frame(width: 30, alignment: .trailing)
                            Image(systemName: slice.node?.isDirectory == true ? "chevron.right" : "minus").font(.system(size: 8)).foregroundColor(.muted).frame(width: 8)
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain).onHover { hoveredID = $0 ? slice.id : nil }.help(slice.node?.url.path ?? "其余较小项目与目录开销")
                }
                Spacer(minLength: 1)
                HStack(spacing: 6) { Image(systemName: "cursorarrow.rays"); Text("内圈是当前目录，外圈是下一层内容") }.font(.system(size: 10)).foregroundColor(.muted)
            }.frame(maxWidth: .infinity).frame(height: 278)
        }.background(GeometryReader { proxy in
            Color.clear.preference(key: NavigationFramesKey.self, value: ["disk-map": proxy.frame(in: .named("MacCleanContent"))])
        })
    }
    private func sector(_ slice: DiskMapSlice, inner: CGFloat, outer: CGFloat) -> some View {
        let shape = RingSector(start: slice.start, end: slice.end, inner: inner, outer: outer)
        return shape.fill(slice.color.opacity(hoveredID == nil || hoveredID == slice.id ? 1 : 0.62))
            .overlay(shape.stroke(Color.white, lineWidth: hoveredID == slice.id ? 2 : 0))
            .allowsHitTesting(false)
    }
    private func slice(at point: CGPoint) -> DiskMapSlice? {
        let dx = point.x - 146, dy = point.y - 146
        let radius = hypot(dx, dy) / 146
        let angle = (atan2(dy, dx) / (2 * .pi) + 1.25).truncatingRemainder(dividingBy: 1)
        let candidates: [DiskMapSlice]
        if radius >= 0.49 && radius <= 0.73 { candidates = slices }
        else if radius >= 0.76 && radius <= 0.98 { candidates = outerSlices }
        else { return nil }
        return candidates.first { angle >= $0.start && angle < $0.end }
    }
    private func activate(_ slice: DiskMapSlice) {
        hoveredID = nil
        if let node = slice.node { model.openMapNode(node) }
        else { model.page = .storage }
    }
}
