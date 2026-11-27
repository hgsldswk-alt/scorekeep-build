import SwiftUI

struct NewTableSheet: View {
    @ObservedObject var store: TableStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: GameKind
    @State private var names: [String]
    @State private var title = ""

    init(store: TableStore) {
        self.store = store
        let kind = store.state.lastKind
        _kind = State(initialValue: kind)
        var names = store.state.lastNames
        while names.count < kind.defaultPlayers { names.append("") }
        _names = State(initialValue: names)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "table.new") { dismiss() }
                Text(L.t("new.kind")).font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(GameKind.allCases, id: \.self) { k in
                        Button { pick(k) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: k.icon).font(.headline).foregroundStyle(k.tint)
                                    .frame(width: 36, height: 36).background(k.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(L.t("kind." + k.rawValue)).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                                    Text(L.t(k.isZeroSum ? "kind.zeroSum" : "kind.free")).font(.caption2).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(minHeight: 60)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(kind == k ? k.tint : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityIdentifier("kind.\(k.rawValue)")
                    }
                }
                HStack {
                    Text(L.t("new.players")).font(.headline)
                    Spacer()
                    Button { if names.count > 2 { names.removeLast() } } label: { Image(systemName: "minus.circle.fill") }
                        .accessibilityIdentifier("players.minus").accessibilityLabel(L.t("players.minus"))
                    Text("\(names.count)").font(.headline.monospacedDigit()).frame(minWidth: 24)
                    Button { if names.count < 12 { names.append("") } } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityIdentifier("players.plus").accessibilityLabel(L.t("players.plus"))
                }.font(.title2).tint(Palette.felt)
                ForEach(names.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Avatar(player: Player(name: names[i].isEmpty ? L.f("player.default", i + 1) : names[i], color: i), size: 34)
                        TextField(L.f("player.default", i + 1), text: $names[i]).font(.headline)
                            .accessibilityIdentifier("player.name.\(i)")
                    }
                    .padding(.horizontal, 14).frame(minHeight: 52)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                TextField(L.t("kind." + kind.rawValue), text: $title)
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("table.title")
                PrimaryButton(key: "new.start", id: "new.start", icon: "play.fill") {
                    store.start(name: title, kind: kind, names: names, rate: store.state.defaultRate)
                    dismiss()
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private func pick(_ k: GameKind) {
        kind = k
        while names.count < k.defaultPlayers { names.append("") }
        if names.count > k.defaultPlayers && names.suffix(names.count - k.defaultPlayers).allSatisfy(\.isEmpty) {
            names = Array(names.prefix(k.defaultPlayers))
        }
    }
}

struct HistorySheet: View {
    @ObservedObject var store: TableStore
    @ObservedObject var access: StoreAccess
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var open: ScoreTable?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(key: "history") { dismiss() }
                let closed = store.closed
                if closed.isEmpty {
                    VStack(spacing: 10) {
                        Chips(size: 40)
                        Text(L.t("history.empty")).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(Array(closed.enumerated()), id: \.element.id) { i, t in
                    let locked = i >= 3 && !access.hasPro
                    Button { if locked { onPro() } else { open = t } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: t.kind.icon).foregroundStyle(t.kind.tint)
                                .frame(width: 40, height: 40).background(t.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.headline).foregroundStyle(Palette.ink)
                                Text(L.f("history.meta", (t.closedAt ?? t.createdAt).formatted(date: .abbreviated, time: .omitted), t.rounds.count))
                                    .font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if locked { Image(systemName: "lock.fill").foregroundStyle(Palette.gold) }
                            else if let top = t.ranking.first {
                                Text("🥇 \(top.name)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            }
                        }.card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.row.\(i)")
                    .contextMenu {
                        Button { store.reopen(t.id); dismiss() } label: { Label(L.t("history.continue"), systemImage: "play") }
                        Button(role: .destructive) { store.delete(t.id) } label: { Label(L.t("delete"), systemImage: "trash") }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .sheet(item: $open) { t in
            SettleSheet(table: t, live: false, access: access, store: store, onPro: onPro)
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var store: TableStore
    @ObservedObject var access: StoreAccess
    var onPro: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "settings") { dismiss() }
                Button(action: onPro) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill").foregroundStyle(Palette.gold)
                            .frame(width: 40, height: 40).background(Palette.goldTint, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t(access.value.purchasedPro ? "store.unlocked" : "pro.title")).font(.headline).foregroundStyle(Palette.ink)
                            Text(L.t("pro.short")).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                    }.card()
                }.buttonStyle(.plain).accessibilityIdentifier("settings.pro")
                row("star.fill", Palette.red, "settings.rate") {
                    if let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
                       let url = ShareQR.storeURL(id).flatMap({ URL(string: $0.absoluteString + "?action=write-review") }) { openURL(url) }
                }
                row("lock.shield.fill", Palette.indigo, "settings.privacy") {
                    if let url = URL(string: "https://hgsldswk-alt.github.io/score-support/") { openURL(url) }
                }
                Text(L.t("settings.local")).font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private func row(_ icon: String, _ color: Color, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(color)
                    .frame(width: 40, height: 40).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(L.t(key)).font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
            }.card()
        }.buttonStyle(.plain).accessibilityIdentifier(key)
    }
}

struct Paywall: View {
    @ObservedObject var access: StoreAccess
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "pro.title") { dismiss() }
                VStack(alignment: .leading, spacing: 8) {
                    Chips(size: 32)
                    Text(L.t(access.value.purchasedPro ? "store.unlocked" : access.hasPro ? "store.trial.title" : "store.trial.end"))
                        .font(.title3.bold())
                    Text(L.t("store.trial.body")).font(.subheadline).opacity(0.9)
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Palette.felt, Palette.felt2], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                feature("clock.arrow.circlepath", Palette.indigo, "pro.f.history")
                feature("yensign.circle.fill", Palette.gold, "pro.f.money")
                feature("photo.fill", Palette.red, "pro.f.card")
                feature("checkmark.seal.fill", Palette.felt, "pro.f.free")
                if !access.value.purchasedPro {
                    if access.mayClaimTrial {
                        SecondaryButton(key: "store.claim", id: "paywall.trial") {
                            Task { await access.purchase(StoreAccess.trialID) }
                        }.disabled(access.working || access.pending || access.productsLoading)
                    }
                    PrimaryButton(key: "store.buy", id: "paywall.buy", icon: "crown.fill") {
                        Task { await access.purchase(StoreAccess.proID) }
                    }.disabled(access.working || access.pending || access.productsLoading)
                    Text(Launch.testing || access.price != nil ? L.f("store.price", access.price ?? "$2.99")
                         : L.t(access.productsLoading ? "loading" : "store.storePrice"))
                        .font(.footnote).foregroundStyle(Palette.muted).accessibilityIdentifier("paywall.price")
                }
                Button(L.t("store.restore")) { Task { await access.restore() } }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(access.working).accessibilityIdentifier("paywall.restore")
                if let message = access.message {
                    Text(L.t(message)).foregroundStyle(Palette.red).accessibilityIdentifier("paywall.message")
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .tint(Palette.felt)
        .task { await access.loadProducts() }
    }

    private func feature(_ icon: String, _ color: Color, _ key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
                .frame(width: 40, height: 40).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(L.t(key)).font(.subheadline).foregroundStyle(Palette.ink)
        }.card()
    }
}
