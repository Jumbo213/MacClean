import SwiftUI
import MacCleanCore

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TitleBlock(title: "相同的内容，留一份就好。", subtitle: "对 1 MiB 及以上的本地文件进行 SHA-256 内容比对，跳过云端占位文件。")
                Spacer(); PrimaryButton(title: "查找重复", symbol: "doc.on.doc") { model.scanDuplicates() }.disabled(model.busy)
            }
            HStack {
                Label(Paths.short(model.duplicateRoot), systemImage: "folder").font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer(); SecondaryButton(title: "选择范围") { model.chooseFolder(forDuplicates: true) }.disabled(model.busy)
            }
            if model.hasDuplicateScan {
                HStack { Text("\(model.duplicates.count) 组重复 · 多余副本占用 \(sizeText(model.duplicates.reduce(0) { $0 + $1.reclaimable }))").font(.system(size: 12)).foregroundColor(.muted); Spacer(); Button("勾选多余副本") { model.duplicateSelection = Set(model.duplicates.flatMap { $0.files.dropFirst().map(\.id) }) }; Button("取消全选") { model.duplicateSelection = [] } }.font(.system(size: 11))
                ScrollView {
                    LazyVStack(spacing: 15) {
                        ForEach(model.duplicates) { group in
                            VStack(spacing: 0) {
                                HStack { Text("\(group.files.count) 个相同文件").font(.system(size: 12, weight: .semibold)); Spacer(); Text("多余 \(sizeText(group.reclaimable))").font(.system(size: 11)).foregroundColor(.muted) }.padding(17).background(Color.mint.opacity(0.4))
                                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                    HStack(spacing: 12) {
                                        CheckBox(checked: model.duplicateSelection.contains(file.id), locked: index == 0) { if !model.duplicateSelection.insert(file.id).inserted { model.duplicateSelection.remove(file.id) } }
                                        IconTile(symbol: "doc", size: 34)
                                        VStack(alignment: .leading, spacing: 4) { Text(file.name).font(.system(size: 12, weight: .medium)); Text(Paths.short(file.url)).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle) }
                                        Spacer()
                                        if index == 0 { Text("保留 · 最新副本").font(.system(size: 9, weight: .medium)).foregroundColor(.accent).padding(6).background(Color.mint).clipShape(Capsule()) }
                                        Text(sizeText(file.logicalBytes)).font(.system(size: 11)).monospacedDigit()
                                        Button { model.reveal(file.url) } label: { Image(systemName: "arrow.up.forward.square").foregroundColor(.muted) }.buttonStyle(.plain)
                                    }.padding(15)
                                    if index < group.files.count - 1 { Divider().padding(.leading, 53) }
                                }
                            }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line))
                        }
                        if model.duplicates.isEmpty { Text("当前范围没有发现符合条件的重复文件。").font(.system(size: 14)).foregroundColor(.muted).padding(65) }
                    }
                }
                HStack { Text("每组始终保留一份。文件用途可能不同，请核对路径。").font(.system(size: 10)).foregroundColor(.muted); Spacer(); PrimaryButton(title: "清理所选 (\(model.duplicateSelection.count))", symbol: "trash") { model.trashDuplicates() }.disabled(model.duplicateSelection.isEmpty || model.busy) }
            } else {
                EmptyPanel(symbol: "doc.on.doc", title: "找到多余的一份", subtitle: "默认从下载文件夹开始。先按文件大小分组，再流式读取内容比对；扫描只读取本地文件，不会主动下载 iCloud 文件。", action: { model.scanDuplicates() }).disabled(model.busy)
            }
        }.padding(32)
    }
}
