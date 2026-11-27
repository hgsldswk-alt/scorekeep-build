import StoreKit
import SwiftUI

@main struct ScoreKeeperApp: App {
    @StateObject private var store = TableStore()
    @StateObject private var access = StoreAccess()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, access: access)
                .task { await access.run() }
                .onOpenURL { url in
                    if let code = url.fragment, !code.isEmpty { store.importCode(code) }
                }
        }
    }
}

enum Sheet: String, Identifiable {
    case record, settle, newTable, history, settings, paywall
    var id: String { rawValue }
}

struct RootView: View {
    @ObservedObject var store: TableStore
    @ObservedObject var access: StoreAccess
    @State private var sheet: Sheet?
    @State private var confirmUndo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let table = store.current {
                        TableBoard(table: table)
                    } else {
                        StartBoard(store: store) { sheet = .newTable }
                    }
                    if let message = store.message {
                        Text(L.t(message)).font(.footnote.weight(.semibold)).foregroundStyle(Palette.felt)
                            .accessibilityIdentifier("store.message")
                            .task { try? await Task.sleep(for: .seconds(3)); store.message = nil }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 120)
            }
            .background(Palette.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .history } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityIdentifier("open.history").accessibilityLabel(L.t("history"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { Task { @MainActor in store.importCode(text) } }
                    }
                    .labelStyle(.iconOnly).tint(Palette.felt)
                    .accessibilityIdentifier("import.paste")
                    Menu {
                        Button { sheet = .newTable } label: { Label(L.t("table.new"), systemImage: "plus") }
                            .accessibilityIdentifier("menu.new")
                        if store.current?.rounds.isEmpty == false {
                            Button(role: .destructive) { confirmUndo = true } label: {
                                Label(L.t("round.undo"), systemImage: "arrow.uturn.backward")
                            }.accessibilityIdentifier("menu.undo")
                        }
                        Button { sheet = .settings } label: { Label(L.t("settings"), systemImage: "gearshape") }
                            .accessibilityIdentifier("menu.settings")
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityIdentifier("open.menu").accessibilityLabel(L.t("more"))
                }
            }
            .tint(Palette.felt)
        }
        .onAppear {
            if let scene = Launch.value("-scene") { sheet = Sheet(rawValue: scene) }
        }
        .confirmationDialog(L.t("round.undo.confirm"), isPresented: $confirmUndo, titleVisibility: .visible) {
            Button(L.t("round.undo"), role: .destructive) { store.undo() }.accessibilityIdentifier("undo.confirm")
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .record:
                if let table = store.current { RecordSheet(table: table) { store.addRound($0) } }
            case .settle:
                if let table = store.current {
                    SettleSheet(table: table, live: true, access: access, store: store) { sheet = .paywall }
                }
            case .newTable: NewTableSheet(store: store)
            case .history: HistorySheet(store: store, access: access) { sheet = .paywall }
            case .settings: SettingsSheet(store: store, access: access) { sheet = .paywall }
            case .paywall: Paywall(access: access)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if store.current != nil {
            HStack(spacing: 10) {
                PrimaryButton(key: "round.record", id: "round.record", icon: "plus.circle.fill") { sheet = .record }
                    .frame(maxWidth: .infinity)
                SecondaryButton(key: "settle", id: "settle.open", icon: "checkmark.seal") { sheet = .settle }
                    .frame(width: 128)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(Palette.paper.opacity(0.96))
        }
    }
}

struct TableBoard: View {
    var table: ScoreTable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(table.name).font(.title2.weight(.heavy)).accessibilityIdentifier("table.name")
                Text(L.f("table.meta", L.t("kind." + table.kind.rawValue), table.players.count, table.rounds.count + 1))
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            hero
            let totals = table.totals
            ForEach(Array(table.ranking.enumerated()), id: \.element.id) { rank, player in
                let total = totals[player.id] ?? 0
                HStack(spacing: 12) {
                    Avatar(player: player)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.headline)
                            if rank == 0 && total > 0 {
                                Text(L.t("rank.first")).font(.caption2.weight(.bold)).foregroundStyle(Palette.gold)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Palette.goldTint, in: Capsule())
                            }
                        }
                        Text(L.f("player.wins", table.wins(player.id))).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text(Fmt.signed(total)).font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.score(total)).monospacedDigit()
                        .accessibilityIdentifier("total.\(rank)")
                }
                .card()
            }
            if !table.rounds.isEmpty {
                Text(L.t("rounds.recent")).font(.subheadline.weight(.bold)).foregroundStyle(Palette.muted).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(table.rounds.enumerated().reversed().prefix(5)), id: \.element.id) { index, round in
                        HStack {
                            Text(L.f("round.n", index + 1)).font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                                .frame(width: 52, alignment: .leading)
                            ForEach(table.players) { p in
                                let v = round.deltas[p.id] ?? 0
                                Text(Fmt.signed(v)).font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(v == 0 ? Palette.muted : Palette.score(v)).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
                .card()
            }
        }
    }

    private var hero: some View {
        let leader = table.ranking.first
        let lead = leader.map { table.total($0.id) } ?? 0
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(lead > 0 ? "hero.leading" : "hero.even")).font(.subheadline).opacity(0.85)
                Text(lead > 0 ? "\(leader?.name ?? "")  \(Fmt.signed(lead))" : L.t("hero.start"))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(table.rate > 0 ? L.f("hero.rounds.rate", table.rounds.count, Fmt.money(table.rate)) : L.f("hero.rounds", table.rounds.count))
                    .font(.footnote).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chips()
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient(colors: [Palette.felt, Palette.felt2], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.felt.opacity(0.28), radius: 10, y: 6)
    }
}

struct StartBoard: View {
    @ObservedObject var store: TableStore
    var onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("app.title")).font(.largeTitle.weight(.heavy)).padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                Chips(size: 34)
                Text(L.t("start.title")).font(.title3.bold())
                Text(L.t("start.body")).font(.subheadline).opacity(0.9)
                Button(action: onNew) {
                    Text(L.t("table.new")).font(.headline).foregroundStyle(Palette.felt)
                        .frame(maxWidth: .infinity, minHeight: 50).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("table.new")
            }
            .foregroundStyle(.white).padding(18)
            .background(LinearGradient(colors: [Palette.felt, Palette.felt2], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(spacing: 10) {
                tip("square.and.arrow.up", "start.tip.share", Palette.red)
                tip("doc.on.clipboard", "start.tip.paste", Palette.indigo)
            }
        }
    }

    private func tip(_ icon: String, _ key: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.headline).foregroundStyle(color)
                .frame(width: 36, height: 36).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(L.t(key)).font(.footnote).foregroundStyle(Palette.ink)
        }.card()
    }
}
