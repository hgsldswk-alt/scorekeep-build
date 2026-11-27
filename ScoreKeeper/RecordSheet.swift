import SwiftUI

struct RecordSheet: View {
    var table: ScoreTable
    var save: ([UUID: Int]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var each: Bool
    @State private var winner: UUID?
    @State private var amount = ""
    @State private var entries: [UUID: String] = [:]
    @State private var error: String?
    @FocusState private var focus: UUID?
    @FocusState private var amountFocused: Bool

    init(table: ScoreTable, save: @escaping ([UUID: Int]) -> Bool) {
        self.table = table
        self.save = save
        _each = State(initialValue: !table.kind.isZeroSum)
    }

    private var ids: [UUID] { table.players.map(\.id) }

    private var preview: [UUID: Int] {
        if each {
            let parsed = Dictionary(uniqueKeysWithValues: ids.map { ($0, Int(entries[$0] ?? "")) })
            if table.kind.isZeroSum { return ScoreMath.autofill(parsed, players: ids) }
            return parsed.mapValues { $0 ?? 0 }
        }
        guard let winner, let value = Int(amount), value > 0 else { return [:] }
        return ScoreMath.splitEven(winner: winner, amount: value, players: ids)
    }

    private var quick: [Int] {
        switch table.kind {
        case .mahjong: return [8, 16, 24, 32, 48, 64]
        case .doudizhu: return [2, 4, 8, 16, 32, 64]
        default: return [5, 10, 20, 50, 100, 200]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(key: "round.title") { dismiss() }
                Text(L.f("round.n", table.rounds.count + 1)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                if table.kind.isZeroSum {
                    Picker("", selection: $each) {
                        Text(L.t("record.split")).tag(false)
                        Text(L.t("record.each")).tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("record.mode")
                }
                if each { eachList } else { splitList }
                if let error {
                    Text(L.t(error)).font(.footnote.weight(.semibold)).foregroundStyle(Palette.red)
                        .accessibilityIdentifier("record.error")
                }
                PrimaryButton(key: "record.save", id: "record.save", icon: "checkmark") { commit() }
                    .opacity(preview.values.contains { $0 != 0 } ? 1 : 0.5)
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
    }

    private var splitList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("record.who")).font(.headline)
            ForEach(Array(table.players.enumerated()), id: \.element.id) { index, p in
                let v = preview[p.id]
                Button {
                    winner = p.id
                    if !Launch.testing { amountFocused = true }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(player: p, size: 36)
                        Text(winner == p.id ? L.f("record.winner", p.name) : p.name).font(.headline).foregroundStyle(Palette.ink)
                        Spacer()
                        if let v {
                            Text(Fmt.signed(v)).font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(Palette.score(v))
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 56)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(winner == p.id ? Palette.felt : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("record.winner.\(index)")
            }
            if winner != nil {
                Text(L.t("record.amount")).font(.headline).padding(.top, 6)
                TextField(L.t("record.amount.placeholder"), text: $amount)
                    .keyboardType(.numberPad).focused($amountFocused)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("record.amount")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(quick, id: \.self) { q in
                            Button { amount = "\(q)" } label: {
                                Text("\(q)")
                                    .font(.headline).foregroundStyle(amount == "\(q)" ? Color.white : Palette.felt)
                                    .padding(.horizontal, 16).frame(minHeight: 40)
                                    .background(amount == "\(q)" ? Palette.felt : Palette.feltTint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                                .accessibilityIdentifier("record.quick.\(q)")
                        }
                    }
                }
            }
        }
    }

    private var eachList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(table.kind.isZeroSum ? "record.each.hint" : "record.each.free")).font(.footnote).foregroundStyle(Palette.muted)
            ForEach(Array(table.players.enumerated()), id: \.element.id) { index, p in
                HStack(spacing: 12) {
                    Avatar(player: p, size: 36)
                    Text(p.name).font(.headline)
                    Spacer()
                    Button {
                        let t = entries[p.id] ?? ""
                        entries[p.id] = t.hasPrefix("-") ? String(t.dropFirst()) : "-" + t
                    } label: {
                        Text("±").font(.headline).foregroundStyle(Palette.indigo).frame(width: 40, height: 40)
                            .background(Palette.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("record.sign.\(index)")
                    TextField(entries[p.id]?.isEmpty == false ? "" : (preview[p.id].map(Fmt.signed) ?? "0"), text: Binding(
                        get: { entries[p.id] ?? "" },
                        set: { entries[p.id] = String($0.filter { $0.isNumber || $0 == "-" }.prefix(7)) }))
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                        .font(.title3.weight(.heavy).monospacedDigit()).frame(width: 96)
                        .focused($focus, equals: p.id)
                        .accessibilityIdentifier("record.entry.\(index)")
                }
                .padding(.horizontal, 14).frame(minHeight: 56)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func commit() {
        let deltas = preview.filter { $0.value != 0 }
        guard !deltas.isEmpty else { error = "record.empty"; return }
        if table.kind.isZeroSum && deltas.values.reduce(0, +) != 0 { error = "record.notZero"; return }
        if save(deltas) { dismiss() } else { error = "record.notZero" }
    }
}
