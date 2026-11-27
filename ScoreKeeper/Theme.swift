import SwiftUI

enum Palette {
    static let felt = color(0x1F6B57)
    static let felt2 = color(0x2A8A6F)
    static let red = color(0xD9443A)
    static let gold = color(0xE2A93B)
    static let indigo = color(0x3B5B9A)
    static let paper = color(0xF4F1EA)
    static let surface = Color.white
    static let ink = color(0x1E2421)
    static let muted = color(0x7A817D)
    static let goldTint = color(0xFBF0DB)
    static let feltTint = color(0xE3F0EB)
    static let avatars: [Color] = [0xD9443A, 0x1F6B57, 0x3B5B9A, 0xE2A93B, 0x8A5A9E, 0x2E8FA6,
                                   0xC46A2B, 0x5B7F3A, 0xB23A6B, 0x44546A, 0x9C7A2E, 0x2F6F8F].map(color)

    static func avatar(_ i: Int) -> Color { avatars[((i % 12) + 12) % 12] }
    static func score(_ v: Int) -> Color { v < 0 ? red : felt }

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum Fmt {
    static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
    static func money(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
    static func initial(_ name: String) -> String {
        let kana = name.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let han = name.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        return ((han && !kana) ? name.last : name.first).map { String($0).uppercased() } ?? "?"
    }
}

struct Card: ViewModifier {
    var fill: Color = Palette.surface
    func body(content: Content) -> some View {
        content.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

extension View { func card(_ fill: Color = Palette.surface) -> some View { modifier(Card(fill: fill)) } }

struct Avatar: View {
    var player: Player
    var size: CGFloat = 40
    var body: some View {
        Text(Fmt.initial(player.name))
            .font(.system(size: size * 0.42, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.avatar(player.color), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct Chips: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach([Palette.red, Palette.gold, Palette.indigo], id: \.self) { c in
                ZStack {
                    Circle().fill(c)
                    Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: size * 0.12, dash: [size * 0.2, size * 0.16]))
                        .padding(size * 0.08)
                    Circle().fill(c).padding(size * 0.3)
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5).padding(size * 0.3)
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 2)
            }
        }
    }
}

struct PrimaryButton: View {
    var key: String
    var id: String
    var icon: String?
    var fill: Color = Palette.felt
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(L.t(key)) } icon: { if let icon { Image(systemName: icon) } }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct SecondaryButton: View {
    var key: String
    var id: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(L.t(key)) } icon: { if let icon { Image(systemName: icon) } }
                .font(.headline)
                .foregroundStyle(Palette.felt)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.felt, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct SheetHeader: View {
    var key: String
    var close: () -> Void
    var body: some View {
        HStack {
            Text(L.t(key)).font(.title2.bold())
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(Palette.muted)
                    .frame(width: 36, height: 36).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("sheet.close").accessibilityLabel(L.t("close"))
        }
    }
}

struct Panel: ViewModifier {
    var fill: Color = Palette.surface
    func body(content: Content) -> some View { content.card(fill) }
}

extension GameKind {
    var icon: String {
        switch self {
        case .mahjong: return "square.grid.2x2.fill"
        case .doudizhu: return "suit.spade.fill"
        case .poker: return "suit.diamond.fill"
        case .general: return "number"
        }
    }
    var tint: Color {
        switch self {
        case .mahjong: return Palette.felt
        case .doudizhu: return Palette.red
        case .poker: return Palette.indigo
        case .general: return Palette.gold
        }
    }
}
