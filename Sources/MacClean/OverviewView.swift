import SwiftUI
import MacCleanCore

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .center) {
                    TitleBlock(title: "给你的 Mac，多一点空间。", subtitle: "看清每一份占用，轻松整理每一天。")
                    Spacer()
                    SecondaryButton(title: "刷新", symbol: "arrow.clockwise") { model.refreshDisk() }
                }.padding(.bottom, 2)
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SMART CLEAN").font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.accent)
                        Text("轻装上阵，刚刚好。").font(.system(size: 26, weight: .bold)).tracking(-0.6)
                        Text(model.hasCleanupScan ? "发现 \(sizeText(model.recommendedBytes)) 可再生成的旧缓存与日志。" : "找出旧缓存、日志与安装包，让整理变得简单。")
                            .font(.system(size: 12)).foregroundColor(.ink.opacity(0.65))
                        HStack(spacing: 12) {
                            PrimaryButton(title: model.hasCleanupScan ? "查看清理建议" : "智能扫描", symbol: "sparkles") {
                                model.page = .cleanup
                                if !model.hasCleanupScan { model.scanCleanup() }
                            }.disabled(model.busy)
                            Text("先预览，再清理").font(.system(size: 10)).foregroundColor(.accent.opacity(0.8))
                        }.padding(.top, 3)
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 140, height: 140)
                        Circle().stroke(Color.accent.opacity(0.10), lineWidth: 1).frame(width: 166, height: 166)
                        Image(systemName: "trash").font(.system(size: 67, weight: .ultraLight)).foregroundColor(.accent)
                        Image(systemName: "sparkle").font(.system(size: 25, weight: .light)).foregroundColor(.accent).offset(x: 47, y: -47)
                    }.frame(width: 180)
                }.padding(28).frame(maxWidth: .infinity, minHeight: 216, alignment: .leading)
                    .background(LinearGradient(colors: [Color.mint, Color(red: 0.92, green: 0.96, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                HStack(alignment: .top, spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack { Text("磁盘使用情况").font(.system(size: 15, weight: .semibold)); Spacer(); Text("Macintosh HD").font(.system(size: 10)).foregroundColor(.muted) }
                            HStack(spacing: 25) {
                                storageRing
                                VStack(alignment: .leading, spacing: 18) {
                                    legend("已使用", color: .accent, bytes: model.usedCapacity)
                                    legend("可用空间", color: Color.line, bytes: model.availableCapacity)
                                }
                            }
                            Divider().overlay(Color.line)
                            HStack { Text("跟随文件夹，发现空间去向").font(.system(size: 10)).foregroundColor(.muted); Spacer(); Button("查看详情 →") { model.page = .storage }.buttonStyle(.plain).foregroundColor(.accent).font(.system(size: 11, weight: .semibold)) }
                        }
                    }
                    VStack(spacing: 15) {
                        quickCard("存储分析", subtitle: "按大小查看每个文件与文件夹", symbol: "chart.bar.xaxis", page: .storage)
                        quickCard("应用管理", subtitle: "程序本体与关联数据，一目了然", symbol: "square.stack.3d.up", page: .apps)
                        quickCard("重复文件", subtitle: "内容比对，保留你需要的一份", symbol: "doc.on.doc", page: .duplicates)
                    }.frame(width: 300)
                }
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield").font(.system(size: 13))
                    Text("你的文件只属于你。所有扫描均在本机完成，无广告，无数据上传。").font(.system(size: 10))
                    Spacer(); Text("MacClean 1.0").font(.system(size: 10))
                }.foregroundColor(.muted).padding(.horizontal, 3).padding(.top, 1)
            }.padding(32)
        }
    }
    private var storageRing: some View {
        ZStack {
            Circle().stroke(Color.line, lineWidth: 13)
            Circle().trim(from: 0, to: model.totalCapacity > 0 ? min(1, Double(model.usedCapacity) / Double(model.totalCapacity)) : 0)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 5) { Text(model.totalCapacity > 0 ? "\(Int(Double(model.usedCapacity) / Double(model.totalCapacity) * 100))%" : "—").font(.system(size: 28, weight: .semibold)).tracking(-1); Text("已使用").font(.system(size: 10)).foregroundColor(.muted) }
        }.frame(width: 132, height: 132).padding(7)
    }
    private func legend(_ title: String, color: Color, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 6, height: 6); Text(title).font(.system(size: 10)).foregroundColor(.muted) }
            Text(sizeText(bytes)).font(.system(size: 21, weight: .semibold)).tracking(-0.6).monospacedDigit()
        }
    }
    private func quickCard(_ title: String, subtitle: String, symbol: String, page: Page) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 13) {
                IconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .semibold)); Text(subtitle).font(.system(size: 10)).foregroundColor(.muted) }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.muted)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 88, alignment: .leading).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line.opacity(0.7)))
        }.buttonStyle(.plain)
    }
}
