import SwiftUI
import MacCleanCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 214)
            VStack(spacing: 0) {
                HStack {
                    Text("MacClean / \(model.page.title)").font(.system(size: 11)).foregroundColor(.muted)
                    Spacer()
                    HStack(spacing: 6) { Circle().fill(Color.accent).frame(width: 5, height: 5); Text("本地处理 · 隐私优先") }
                        .font(.system(size: 10)).foregroundColor(.muted)
                }.padding(.horizontal, 32).frame(height: 57)
                Divider().overlay(Color.line)
                if model.busy { progressBanner }
                if let notice = model.notice { noticeBanner(notice) }
                Group {
                    switch model.page {
                    case .overview: OverviewView()
                    case .storage: StorageView()
                    case .apps: AppsView()
                    case .cleanup: CleanupView()
                    case .duplicates: DuplicatesView()
                    case .history: HistoryView()
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color.canvas)
        }.foregroundColor(.ink).tint(.accent)
            .coordinateSpace(name: "MacCleanContent")
            .onPreferenceChange(NavigationFramesKey.self) { model.navigationFrames = $0 }
            .sheet(isPresented: $model.showingReview) { ReviewSheet().environmentObject(model) }
            .sheet(isPresented: $model.showingDetails) { detailsSheet }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TrashMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacClean").font(.system(size: 19, weight: .bold)).tracking(-0.5)
                    Text("让空间，回归轻盈").font(.system(size: 9)).foregroundColor(.muted)
                }
            }.padding(.top, 52).padding(.bottom, 34).padding(.horizontal, 20)
            Text("我的 MAC").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundColor(.muted).padding(.leading, 28).padding(.bottom, 13)
            ForEach(Array(Page.allCases.dropLast()), id: \.self) { page in
                NavigationRow(page: page, selected: model.page == page) { model.page = page }
                    .padding(.horizontal, 14).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "internaldrive"); Text("Macintosh HD").fontWeight(.medium) }.font(.system(size: 11))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.line)
                        Capsule().fill(Color.accent.opacity(0.6)).frame(width: proxy.size.width * CGFloat(model.totalCapacity > 0 ? Double(model.usedCapacity) / Double(model.totalCapacity) : 0))
                    }
                }.frame(height: 4)
                Text("\(sizeText(model.availableCapacity)) 可用 / \(sizeText(model.totalCapacity))").font(.system(size: 9)).foregroundColor(.muted)
            }.padding(15).background(Color.canvas).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 18).padding(.bottom, 17)
            NavigationRow(page: .settings, selected: model.page == .settings) { model.page = .settings }
                .padding(.horizontal, 14).padding(.bottom, 17)
        }.background(Color.white).overlay(alignment: .trailing) { Color.line.frame(width: 1) }
    }
    private var progressBanner: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.operation) · 已处理 \(model.scannedCount) 项").font(.system(size: 12, weight: .medium))
                Text(model.progressPath).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(); if model.canCancel { Button("停止") { model.cancel() }.buttonStyle(.bordered).controlSize(.small) }
        }.padding(14).background(Color.tintSurface)
    }
    private func noticeBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle").foregroundColor(.accent)
            Text(text).font(.system(size: 11)).lineSpacing(3).textSelection(.enabled)
            Spacer()
            Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
        }.padding(12).background(Color.tintSurface.opacity(0.65))
    }
    private var detailsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("操作详情").font(.title2.bold())
            ScrollView { Text(model.details.joined(separator: "\n\n")).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 240)
            HStack { Spacer(); Button("关闭") { model.showingDetails = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620, height: 430)
    }
}

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 15) { IconTile(symbol: "trash", size: 52); VStack(alignment: .leading, spacing: 6) {
                Text("确认移到废纸篓").font(.system(size: 23, weight: .bold))
                Text("\(model.pending.count) 个项目 · \(sizeText(model.pendingBytes))").font(.system(size: 13)).foregroundColor(.muted)
            } }
            Text("请确认下列文件已不再需要。你可以在「清理记录」中恢复；清空废纸篓后无法恢复，空间也会在那时释放。应用关联数据可能包含个人文件。").font(.system(size: 12)).foregroundColor(.muted).lineSpacing(5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.pending) { item in HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)); Text(item.url.path).font(.system(size: 10)).foregroundColor(.muted).textSelection(.enabled) }
                        Spacer(); Text(sizeText(item.bytes)).font(.system(size: 12)).monospacedDigit()
                    }; Divider() }
                }.padding(14)
            }.frame(height: 220).background(Color.canvas).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Button("取消") { model.showingReview = false }.keyboardShortcut(.cancelAction); Spacer(); PrimaryButton(title: "移到废纸篓", symbol: "trash") { model.confirmTrash() } }
        }.padding(30).frame(width: 620)
    }
}
