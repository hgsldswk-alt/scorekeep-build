import XCTest

final class ScoreCoreTests: XCTestCase {
    private func table(_ kind: GameKind = .mahjong, names: [String] = ["阿明", "小玲", "大强", "阿芳"]) -> ScoreTable {
        ScoreTable(name: "周五麻将局", kind: kind, players: names.enumerated().map { Player(name: $1, color: $0) })
    }

    func testSplitEvenIsZeroSumWithRemainder() {
        let t = table(), ids = t.players.map(\.id)
        let d = ScoreMath.splitEven(winner: ids[1], amount: 25, players: ids)
        XCTAssertEqual(d[ids[1]], 25)
        XCTAssertEqual(d.values.reduce(0, +), 0)
        XCTAssertEqual(Set([d[ids[0]]!, d[ids[2]]!, d[ids[3]]!]), [-9, -8])
        let neg = ScoreMath.splitEven(winner: ids[0], amount: -10, players: ids)
        XCTAssertEqual(neg.values.reduce(0, +), 0)
        XCTAssertTrue(ScoreMath.splitEven(winner: ids[0], amount: 0, players: ids).isEmpty)
    }

    func testAutofillOnlyWhenExactlyOneMissing() {
        let ids = table().players.map(\.id)
        let filled = ScoreMath.autofill([ids[0]: 24, ids[1]: -8, ids[2]: -8], players: ids)
        XCTAssertEqual(filled[ids[3]], -8)
        let two = ScoreMath.autofill([ids[0]: 24, ids[1]: -8], players: ids)
        XCTAssertEqual(two[ids[2]], 0)
        XCTAssertEqual(two[ids[3]], 0)
    }

    func testAddRejectsNonZeroSumAndUndo() {
        var t = table()
        let ids = t.players.map(\.id)
        XCTAssertFalse(t.add([ids[0]: 10, ids[1]: -5]))
        XCTAssertTrue(t.add([ids[0]: 10, ids[1]: -10]))
        XCTAssertFalse(t.add([ids[0]: 0]))
        XCTAssertFalse(t.add([UUID(): 5, ids[0]: -5]))
        var g = table(.general)
        XCTAssertTrue(g.add([g.players[0].id: 7]))
        XCTAssertEqual(t.undo()?.deltas[ids[0]], 10)
        XCTAssertTrue(t.rounds.isEmpty)
    }

    func testTotalsRankingAndSettlementMatchDesign() {
        var t = table()
        let ids = t.players.map(\.id)
        XCTAssertTrue(t.add([ids[0]: 86, ids[1]: 12, ids[2]: -30, ids[3]: -68]))
        XCTAssertEqual(t.ranking.map(\.name), ["阿明", "小玲", "大强", "阿芳"])
        let s = ScoreMath.settle(t.totals, order: ids)
        XCTAssertEqual(s, [Transfer(from: ids[3], to: ids[0], amount: 68),
                           Transfer(from: ids[2], to: ids[0], amount: 18),
                           Transfer(from: ids[2], to: ids[1], amount: 12)])
        XCTAssertLessThanOrEqual(s.count, ids.count - 1)
        XCTAssertEqual(ScoreMath.money(-68, rate: 0.5), -34)
        XCTAssertEqual(t.wins(ids[0]), 1)
    }

    func testSettlementBalancesRandomTables() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var t = table()
            let ids = t.players.map(\.id)
            for _ in 0..<Int.random(in: 1...20, using: &rng) {
                let w = ids.randomElement(using: &rng)!
                t.add(ScoreMath.splitEven(winner: w, amount: Int.random(in: 1...300, using: &rng), players: ids))
            }
            var bal = t.totals
            for tr in ScoreMath.settle(bal, order: ids) {
                XCTAssertGreaterThan(tr.amount, 0)
                bal[tr.from]! += tr.amount
                bal[tr.to]! -= tr.amount
            }
            XCTAssertTrue(bal.values.allSatisfy { $0 == 0 })
        }
    }

    func testCodeRoundTripFromLinkMessageAndRawCode() throws {
        var t = table()
        t.rate = 1
        let ids = t.players.map(\.id)
        t.add([ids[0]: 30, ids[1]: -10, ids[2]: -10, ids[3]: -10])
        t.add([ids[0]: -8, ids[1]: 24, ids[2]: -8, ids[3]: -8])
        for text in [TableCode.link(for: t), "看结果 " + TableCode.message(for: t) + " 下周见", TableCode.code(for: t)] {
            let back = try XCTUnwrap(TableCode.decode(text), text)
            XCTAssertEqual(back.name, t.name)
            XCTAssertEqual(back.players.map(\.name), t.players.map(\.name))
            XCTAssertEqual(back.ranking.map(\.name), t.ranking.map(\.name))
            XCTAssertEqual(back.players.map { back.total($0.id) }, t.players.map { t.total($0.id) })
            XCTAssertEqual(back.rate, 1)
        }
        let web = try XCTUnwrap(TableCode.decode("https://hgsldswk-alt.github.io/score-support/j.html#q1YqU7Iy1FHKU7JSejpxxZNdU17u2v10Q9vTjQ1KOkrZQNHcxIys_Lx0IK9AySpa6eWM_c9m9AF5Tzf0P-_bBGIsWf50zy4gAyj1omuzUqyOUjJQpYGOoY6RjjGQVwTkRRsb6OgawnGsTrSpmY6RkY6uEZBvahELVJYLdEgtAA"))
        XCTAssertEqual(web.players.map { web.total($0.id) }, [86, 12, -30, -68])
        XCTAssertNil(TableCode.decode("随便一段话"))
        XCTAssertNil(TableCode.decode(TableCode.marker + "abc#"))
    }
}
