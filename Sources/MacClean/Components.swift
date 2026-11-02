import SwiftUI
import MacCleanCore

// Disambiguate the classic property wrapper from newer SDK State macros.
typealias ViewState<Value> = SwiftUI.State<Value>

enum AppTheme {
    static let chart: [Color] = [Color(red: 0.43, green: 0.38, blue: 0.88), Color(red: 0.28, green: 0.52, blue: 0.91),
                                Color(red: 0.25, green: 0.66, blue: 0.75), Color(red: 0.94, green: 0.65, blue: 0.35),
                                Color(red: 0.83, green: 0.43, blue: 0.64), Color(red: 0.55, green: 0.56, blue: 0.75),
                                Color(red: 0.58, green: 0.64, blue: 0.73), Color(red: 0.78, green: 0.80, blue: 0.85)]
}

extension Color {
    static let ink = Color(red: 0.14, green: 0.15, blue: 0.20)
    static let muted = Color(red: 0.47, green: 0.49, blue: 0.56)
    static let accent = Color(red: 0.38, green: 0.34, blue: 0.81)
    static let tintSurface = Color(red: 0.93, green: 0.93, blue: 0.985)
    static let canvas = Color(red: 0.96, green: 0.965, blue: 0.98)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.93)
}

struct NavigationFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}

struct NavigationRow: View {
    let page: Page
    let selected: Bool
    let action: () -> Void
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.symbol).font(.system(size: 15, weight: selected ? .semibold : .regular)).frame(width: 20)
                Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if selected { RoundedRectangle(cornerRadius: 2).fill(Color.accent).frame(width: 3, height: 15) }
            }
            .foregroundColor(selected ? .accent : .ink.opacity(0.76))
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 45)
            .background(selected ? Color.tintSurface : (hovered ? Color.canvas : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityIdentifier("nav-" + page.rawValue)
        .accessibilityLabel(page.title)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: NavigationFramesKey.self, value: [page.rawValue: proxy.frame(in: .named("MacCleanContent"))])
        })
    }
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
        }.buttonStyle(.plain).padding(5).contentShape(Rectangle()).disabled(locked).accessibilityLabel(checked ? "取消选择" : "选择")
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
