import Foundation
import SwiftUI

enum ScoreError: String, Error { case storage }

struct SavedState: Codable, Equatable {
    var tables: [ScoreTable] = []
    var lastNames: [String] = []
    var lastKind: GameKind = .mahjong
    var defaultRate: Double = 0
}

@MainActor final class TableStore: ObservableObject {
    @Published private(set) var state = SavedState()
    @Published var message: String?
    private let url: URL

    init(url: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? folder.appendingPathComponent("tables.json")
        if Launch.has("-reset") { try? FileManager.default.removeItem(at: self.url) }
        if let data = try? Data(contentsOf: self.url), let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = saved
        }
        if Launch.has("-demo") { state = Self.demo() }
    }

    var current: ScoreTable? { state.tables.last { $0.closedAt == nil } }
    var closed: [ScoreTable] { state.tables.filter { $0.closedAt != nil }.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) } }

    func start(name: String, kind: GameKind, names: [String], rate: Double) {
        let clean = names.map { $0.trimmingCharacters(in: .whitespaces) }.enumerated()
            .map { $1.isEmpty ? L.f("player.default", $0 + 1) : String($1.prefix(16)) }
        var table = ScoreTable(name: name.isEmpty ? L.t("kind." + kind.rawValue) : String(name.prefix(30)), kind: kind,
                               players: clean.enumerated().map { Player(name: $1, color: $0 % 12) })
        table.rate = rate
        mutate {
            for i in $0.tables.indices where $0.tables[i].closedAt == nil { $0.tables[i].closedAt = Date() }
            $0.tables.append(table)
            $0.lastNames = clean
            $0.lastKind = kind
            $0.defaultRate = rate
        }
    }

    @discardableResult
    func addRound(_ deltas: [UUID: Int]) -> Bool {
        guard let id = current?.id else { return false }
        var ok = false
        update(id) { ok = $0.add(deltas) }
        return ok
    }

    func undo() { if let id = current?.id { update(id) { $0.undo() } } }

    func setRate(_ rate: Double) {
        guard let id = current?.id else { return }
        update(id) { $0.rate = max(0, rate) }
        mutate { $0.defaultRate = max(0, rate) }
    }

    func close() { if let id = current?.id { update(id) { $0.closedAt = Date() } } }

    func reopen(_ id: UUID) {
        mutate {
            for i in $0.tables.indices where $0.tables[i].closedAt == nil { $0.tables[i].closedAt = Date() }
            if let i = $0.tables.firstIndex(where: { $0.id == id }) {
                var t = $0.tables.remove(at: i)
                t.closedAt = nil
                $0.tables.append(t)
            }
        }
    }

    func delete(_ id: UUID) { mutate { $0.tables.removeAll { $0.id == id } } }

    @discardableResult
    func importCode(_ text: String) -> Bool {
        guard let table = TableCode.decode(text) else { message = "import.bad"; return false }
        mutate {
            for i in $0.tables.indices where $0.tables[i].closedAt == nil { $0.tables[i].closedAt = Date() }
            $0.tables.append(table)
        }
        message = "import.done"
        return true
    }

    private func update(_ id: UUID, _ change: (inout ScoreTable) -> Void) {
        mutate { s in if let i = s.tables.firstIndex(where: { $0.id == id }) { change(&s.tables[i]) } }
    }

    private func mutate(_ change: (inout SavedState) -> Void) {
        var copy = state
        change(&copy)
        state = copy
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(copy).write(to: url, options: .atomic)
        } catch { message = "error.storage" }
    }

    static func demo() -> SavedState {
        let names = L.t("demo.names").components(separatedBy: ",")
        var t = ScoreTable(name: L.t("demo.table"), kind: .mahjong,
                           players: names.prefix(4).enumerated().map { Player(name: $1, color: $0) })
        t.rate = 1
        let ids = t.players.map(\.id)
        for row in [[30, -10, -10, -10], [-8, 24, -8, -8], [48, -16, -16, -16], [-12, -12, 36, -12], [16, 34, -20, -30], [12, -8, -12, 8]] {
            t.add(Dictionary(uniqueKeysWithValues: zip(ids, row)))
        }
        var old = ScoreTable(name: L.t("demo.old"), kind: .doudizhu,
                             players: names.prefix(3).enumerated().map { Player(name: $1, color: $0) })
        let o = old.players.map(\.id)
        old.add([o[0]: 40, o[1]: -20, o[2]: -20])
        old.closedAt = Date().addingTimeInterval(-86_400 * 3)
        var past: [ScoreTable] = [old]
        for (i, rows) in [[[24, -8, -8, -8], [-16, 48, -16, -16]], [[-6, -6, 18, -6]], [[10, -30, 10, 10], [32, -8, -16, -8]]].enumerated() {
            var p = ScoreTable(name: L.t(["demo.p1", "demo.p2", "demo.p3"][i]), kind: i == 1 ? .poker : .mahjong,
                               players: names.prefix(4).enumerated().map { Player(name: $1, color: $0) })
            let ids = p.players.map(\.id)
            for r in rows { p.add(Dictionary(uniqueKeysWithValues: zip(ids, r))) }
            p.closedAt = Date().addingTimeInterval(-86_400 * Double(7 * (i + 1)))
            past.append(p)
        }
        return SavedState(tables: past + [t], lastNames: Array(names.prefix(4)), lastKind: .mahjong, defaultRate: 1)
    }
}
