import SwiftUI
import MacCleanCore

// Disambiguate the classic property wrapper from newer SDK State macros.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.21)
    static let muted = Color(red: 0.47, green: 0.53, blue: 0.54)
    static let accent = Color(red: 0.09, green: 0.47, blue: 0.38)
    static let mint = Color(red: 0.89, green: 0.95, blue: 0.92)
    static let canvas = Color(red: 0.965, green: 0.975, blue: 0.971)
    static let line = Color(red: 0.90, green: 0.93, blue: 0.91)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.line.opacity(0.7), lineWidth: 1))
    }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String = "arrow.clockwise"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 17).padding(.vertical, 12)
                .foregroundColor(.white).background(Color.accent).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
struct SecondaryButton: View {
    let title: String
    var symbol: String = "folder"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 10)
                .foregroundColor(.ink).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
struct IconTile: View {
    let symbol: String
    var color: Color = .accent
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.40, weight: .medium))
            .foregroundColor(color).frame(width: size, height: size)
            .background(color.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: size * 0.27))
    }
}
struct TrashMark: View {
    var body: some View {
        Image(systemName: "trash").font(.system(size: 27, weight: .light)).foregroundColor(.ink)
            .frame(width: 52, height: 52).background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.line))
    }
}
struct EmptyPanel: View {
    let symbol: String
    let title: String
    let subtitle: String
    var button: String = "开始扫描"
    let action: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            IconTile(symbol: symbol, size: 72)
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundColor(.ink)
            Text(subtitle).font(.system(size: 13)).foregroundColor(.muted).multilineTextAlignment(.center).lineSpacing(6).frame(maxWidth: 480)
            PrimaryButton(title: button, symbol: "magnifyingglass", action: action).padding(.top, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(35)
    }
}
struct TitleBlock: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.8).foregroundColor(.ink)
            Text(subtitle).font(.system(size: 13)).foregroundColor(.muted)
        }
    }
}
struct CheckBox: View {
    let checked: Bool
    var locked = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 18)).foregroundColor(locked ? .line : (checked ? .accent : .muted.opacity(0.55)))
        }.buttonStyle(.plain).disabled(locked).accessibilityLabel(checked ? "取消选择" : "选择")
    }
}
struct DataRow: View {
    @EnvironmentObject var model: AppModel
    let item: CleanupItem
    let checked: Bool
    let toggle: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            CheckBox(checked: checked, action: toggle)
            IconTile(symbol: item.category == "旧安装包" ? "shippingbox" : "doc")
            VStack(alignment: .leading, spacing: 5) {
                Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundColor(.ink)
                Text(Paths.short(item.url)).font(.system(size: 11)).foregroundColor(.muted).lineLimit(1).truncationMode(.middle)
                Text(item.reason).font(.system(size: 10)).foregroundColor(.muted).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(sizeText(item.bytes)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundColor(.ink)
            Button { model.reveal(item.url) } label: { Image(systemName: "arrow.up.forward.square").foregroundColor(.muted) }.buttonStyle(.plain).help("在 Finder 中显示")
        }.padding(.vertical, 13).padding(.horizontal, 18)
    }
}
