import StoreKit
import SwiftUI
import UIKit

struct SettleSheet: View {
    var table: ScoreTable
    var live: Bool
    @ObservedObject var access: StoreAccess
    @ObservedObject var store: TableStore
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var rateText = ""
    @State private var copied = false
    @State private var image: Image?

    private var rate: Double { access.hasPro ? (Double(rateText.replacingOccurrences(of: ",", with: ".")) ?? 0) : 0 }
    private var priced: ScoreTable { var t = table; t.rate = rate; return t }
    private var transfers: [Transfer] { ScoreMath.settle(table.totals, order: table.players.map(\.id)) }
    private func name(_ id: UUID) -> Player? { table.players.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "settle.title") { dismiss() }
                Text(L.f("settle.meta", table.name, table.rounds.count)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                rateRow
                if transfers.isEmpty {
                    Text(L.t("settle.even")).font(.headline).card()
                }
                ForEach(Array(transfers.enumerated()), id: \.offset) { i, t in
                    if let from = name(t.from), let to = name(t.to) {
                        HStack(spacing: 12) {
                            Avatar(player: from)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(L.t("settle.gives")).font(.caption).foregroundStyle(Palette.muted)
                                Text(rate > 0 ? L.f("money", Fmt.money(ScoreMath.money(t.amount, rate: rate))) : L.f("points", t.amount))
                                    .font(.title2.weight(.heavy).monospacedDigit())
                                    .accessibilityIdentifier("settle.amount.\(i)")
                                Text("\(from.name) → \(to.name)").font(.caption2).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Avatar(player: to)
                        }.card()
                    }
                }
                if transfers.count > 1 {
                    Text(L.f("settle.fewest", transfers.count)).font(.footnote).foregroundStyle(Palette.muted)
                }
                Text(L.t("share.title")).font(.headline).padding(.top, 6)
                HStack(spacing: 10) {
                    if let image {
                        ShareLink(item: image, preview: SharePreview(table.name, image: image)) {
                            tile(icon: "photo.fill", key: "share.image", sub: "share.image.sub", color: Palette.red)
                        }.buttonStyle(.plain).accessibilityIdentifier("share.image")
                    }
                    if let url = URL(string: TableCode.link(for: priced)) {
                        ShareLink(item: url, message: Text(L.f("share.message", table.name))) {
                            tile(icon: "link", key: "share.link", sub: "share.link.sub", color: Palette.indigo)
                        }.buttonStyle(.plain).accessibilityIdentifier("share.link")
                    }
                }
                Button {
                    UIPasteboard.general.string = TableCode.message(for: priced)
                    copied = true
                } label: {
                    Label(L.t(copied ? "share.copied" : "share.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.felt)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("share.copy")
                if live {
                    PrimaryButton(key: "settle.close", id: "settle.close", icon: "flag.checkered", fill: Palette.ink) {
                        store.setRate(rate)
                        store.close()
                        if store.closed.count == 3 && !Launch.testing { requestReview() }
                        dismiss()
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .onAppear {
            if rateText.isEmpty, table.rate > 0 { rateText = Fmt.money(table.rate) }
            render()
        }
        .onChange(of: rateText) { render() }
    }

    private var rateRow: some View {
        HStack {
            Image(systemName: "yensign.circle.fill").foregroundStyle(Palette.gold)
            Text(L.t("settle.rate")).font(.headline)
            Spacer()
            if access.hasPro {
                TextField("0", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .font(.title3.weight(.heavy)).frame(width: 90).accessibilityIdentifier("settle.rate")
            } else {
                Button(L.t("pro.unlock")) { onPro() }.font(.subheadline.weight(.bold)).accessibilityIdentifier("settle.rate.pro")
            }
        }
        .card(Palette.goldTint)
    }

    private func tile(icon: String, key: String, sub: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 44, height: 44).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(L.t(key)).font(.headline).foregroundStyle(Palette.ink)
            Text(L.t(sub)).font(.caption2).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: ResultCard(table: priced, watermark: !access.hasPro).frame(width: 390))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}

struct ResultCard: View {
    var table: ScoreTable
    var watermark: Bool

    var body: some View {
        let totals = table.totals
        let transfers = ScoreMath.settle(totals, order: table.players.map(\.id))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name).font(.title2.weight(.heavy))
                    Text(L.f("card.meta", table.rounds.count, table.createdAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption).opacity(0.85)
                }
                Spacer()
                Chips(size: 26)
            }
            .foregroundStyle(.white).padding(16)
            .background(LinearGradient(colors: [Palette.felt, Palette.felt2], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18))
            ForEach(Array(table.ranking.enumerated()), id: \.element.id) { rank, p in
                let v = totals[p.id] ?? 0
                HStack(spacing: 10) {
                    Text(["🥇", "🥈", "🥉"].indices.contains(rank) ? ["🥇", "🥈", "🥉"][rank] : "  ").font(.title3)
                    Avatar(player: p, size: 32)
                    Text(p.name).font(.headline)
                    Spacer()
                    Text(Fmt.signed(v)).font(.title2.weight(.heavy).monospacedDigit()).foregroundStyle(Palette.score(v))
                }
            }
            if !transfers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("settle.title")).font(.subheadline.weight(.bold))
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, t in
                        let from = table.players.first { $0.id == t.from }?.name ?? ""
                        let to = table.players.first { $0.id == t.to }?.name ?? ""
                        Text("\(from) → \(to)  " + (table.rate > 0 ? L.f("money", Fmt.money(ScoreMath.money(t.amount, rate: table.rate))) : L.f("points", t.amount)))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.goldTint, in: RoundedRectangle(cornerRadius: 14))
            }
            if table.rounds.count > 0 {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("#").foregroundStyle(Palette.muted)
                        ForEach(table.players) { Text($0.name).lineLimit(1) }
                    }.font(.caption.weight(.bold))
                    ForEach(Array(table.rounds.suffix(20).enumerated()), id: \.element.id) { i, r in
                        GridRow {
                            Text("\(table.rounds.count - min(table.rounds.count, 20) + i + 1)").foregroundStyle(Palette.muted)
                            ForEach(table.players) { p in
                                let v = r.deltas[p.id] ?? 0
                                Text(Fmt.signed(v)).foregroundStyle(v == 0 ? Palette.muted : Palette.score(v))
                            }
                        }.font(.caption.monospacedDigit())
                    }
                }
                .padding(10).frame(maxWidth: .infinity).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 12) {
                if let url = URL(string: TableCode.link(for: table)), let qr = ShareQR.image(for: url, scale: 3) {
                    Image(decorative: qr, scale: 1).interpolation(.none).resizable().frame(width: 92, height: 92)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("card.scan")).font(.footnote.weight(.semibold))
                    Text(L.t("card.tags")).font(.caption).foregroundStyle(Palette.felt)
                    if watermark { Text(L.t("card.watermark")).font(.caption2).foregroundStyle(Palette.muted) }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .background(Palette.paper)
    }
}
