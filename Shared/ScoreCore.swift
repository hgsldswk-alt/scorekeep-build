import Foundation


enum GameKind: String, Codable, CaseIterable, Sendable {
    case mahjong, doudizhu, poker, general

    var defaultPlayers: Int {
        switch self {
        case .mahjong: return 4
        case .doudizhu: return 3
        case .poker: return 4
        case .general: return 4
        }
    }

    var isZeroSum: Bool { self != .general }
}

struct Player: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var color: Int
}

struct Round: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var deltas: [UUID: Int]
    var date = Date()

    var sum: Int { deltas.values.reduce(0, +) }
}

struct Transfer: Equatable, Sendable {
    var from: UUID
    var to: UUID
    var amount: Int
}

struct ScoreTable: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var kind: GameKind
    var players: [Player]
    var rounds: [Round] = []
    var rate: Double = 0
    var createdAt = Date()
    var closedAt: Date? = nil


    func total(_ player: UUID) -> Int { rounds.reduce(0) { $0 + ($1.deltas[player] ?? 0) } }

    var totals: [UUID: Int] { Dictionary(uniqueKeysWithValues: players.map { ($0.id, total($0.id)) }) }

    var ranking: [Player] {
        let t = totals
        return players.enumerated().sorted { a, b in
            let x = t[a.element.id] ?? 0, y = t[b.element.id] ?? 0
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    func wins(_ player: UUID) -> Int { rounds.filter { ($0.deltas[player] ?? 0) > 0 }.count }


    @discardableResult
    mutating func add(_ deltas: [UUID: Int], date: Date = Date()) -> Bool {
        let known = Set(players.map(\.id))
        guard !deltas.isEmpty, Set(deltas.keys).isSubset(of: known),
              deltas.values.contains(where: { $0 != 0 }) else { return false }
        if kind.isZeroSum && deltas.values.reduce(0, +) != 0 { return false }
        rounds.append(Round(deltas: deltas, date: date))
        return true
    }

    @discardableResult
    mutating func undo() -> Round? { rounds.popLast() }
}

enum ScoreMath {
    static func autofill(_ entries: [UUID: Int?], players: [UUID]) -> [UUID: Int] {
        let missing = players.filter { entries[$0] == nil || entries[$0]! == nil }
        var out: [UUID: Int] = [:]
        for p in players { out[p] = (entries[p] ?? nil) ?? 0 }
        if missing.count == 1 {
            out[missing[0]] = -players.filter { $0 != missing[0] }.reduce(0) { $0 + (out[$1] ?? 0) }
        }
        return out
    }

    static func splitEven(winner: UUID, amount: Int, players: [UUID]) -> [UUID: Int] {
        let losers = players.filter { $0 != winner }
        guard !losers.isEmpty, amount != 0 else { return [:] }
        var out: [UUID: Int] = [winner: amount]
        let base = amount / losers.count, extra = abs(amount % losers.count)
        let step = amount >= 0 ? 1 : -1
        for (i, p) in losers.enumerated() {
            out[p] = -(base + (i < extra ? step : 0))
        }
        return out
    }

    static func settle(_ totals: [UUID: Int], order: [UUID]) -> [Transfer] {
        var debtors = order.compactMap { id -> (UUID, Int)? in
            let v = totals[id] ?? 0; return v < 0 ? (id, -v) : nil
        }
        var creditors = order.compactMap { id -> (UUID, Int)? in
            let v = totals[id] ?? 0; return v > 0 ? (id, v) : nil
        }
        var out: [Transfer] = []
        while !debtors.isEmpty, !creditors.isEmpty {
            debtors.sort { $0.1 > $1.1 }
            creditors.sort { $0.1 > $1.1 }
            let pay = min(debtors[0].1, creditors[0].1)
            out.append(Transfer(from: debtors[0].0, to: creditors[0].0, amount: pay))
            debtors[0].1 -= pay
            creditors[0].1 -= pay
            debtors.removeAll { $0.1 == 0 }
            creditors.removeAll { $0.1 == 0 }
        }
        return out
    }

    static func money(_ points: Int, rate: Double) -> Double {
        (Double(points) * rate * 100).rounded() / 100
    }
}

enum TableCode {
    static let marker = "#SCORE1#"
    static let linkBase = "https://hgsldswk-alt.github.io/score-support/j.html#"

    private struct Payload: Codable {
        var v: Int
        var n: String
        var k: String
        var p: [String]
        var c: [Int]
        var r: [[Int]]
        var m: Double
    }

    static func code(for table: ScoreTable) -> String {
        let ids = table.players.map(\.id)
        let payload = Payload(v: 1, n: table.name, k: table.kind.rawValue,
                              p: table.players.map(\.name), c: table.players.map(\.color),
                              r: table.rounds.map { r in ids.map { r.deltas[$0] ?? 0 } }, m: table.rate)
        guard let json = try? JSONEncoder().encode(payload) else { return "" }
        let packed = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        return base64url(packed)
    }

    static func link(for table: ScoreTable) -> String { linkBase + code(for: table) }

    static func message(for table: ScoreTable) -> String { "\(table.name) \(marker)\(code(for: table))#" }

    static func decode(_ text: String) -> ScoreTable? {
        guard text.count <= 20_000 else { return nil }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = raw.range(of: marker) {
            raw = String(raw[r.upperBound...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        } else if let r = raw.range(of: "j.html#") {
            raw = String(raw[r.upperBound...])
        }
        guard !raw.isEmpty, let packed = fromBase64url(raw) else { return nil }
        let json = (try? (packed as NSData).decompressed(using: .zlib) as Data) ?? packed
        guard json.count <= 200_000, let p = try? JSONDecoder().decode(Payload.self, from: json),
              p.v == 1, (2...12).contains(p.p.count), p.c.count == p.p.count, p.r.count <= 2000,
              p.r.allSatisfy({ $0.count == p.p.count }), let kind = GameKind(rawValue: p.k) else { return nil }
        let players = zip(p.p, p.c).map { Player(name: String($0.prefix(16)), color: max(0, min($1, 11))) }
        var table = ScoreTable(name: String(p.n.prefix(30)), kind: kind, players: players, rate: max(0, p.m))
        table.rounds = p.r.map { row in Round(deltas: Dictionary(uniqueKeysWithValues: zip(players.map(\.id), row))) }
        return table
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
