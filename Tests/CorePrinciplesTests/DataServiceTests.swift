import XCTest
import GRDB
@testable import CorePrinciplesLib

final class DataServiceTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var service: DataService!

    override func setUpWithError() throws {
        dbQueue = try DatabaseQueue()
        _ = try AppDatabase(dbQueue: dbQueue)
        service = DataService(dbQueue: dbQueue)
    }

    // MARK: - Migration

    func testMigrationCreatesTablesAndIndex() throws {
        try dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("principles"))
            XCTAssertTrue(try db.tableExists("entries"))
            let indexes = try db.indexes(on: "entries")
            XCTAssertTrue(indexes.contains { $0.name == "idx_entries_principle_created" })
        }
    }

    func testMigrationIsIdempotent() throws {
        _ = try AppDatabase(dbQueue: dbQueue)
        try dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("principles"))
        }
    }

    // MARK: - addPrinciple

    func testAddPrincipleCreatesActive() throws {
        let p = try service.addPrinciple(text: "Be patient")
        XCTAssertNotNil(p.id)
        XCTAssertEqual(p.text, "Be patient")
        XCTAssertEqual(p.state, .active)
        XCTAssertNil(p.lastAskedAt)
    }

    // MARK: - listPrinciples

    func testListPrinciplesActiveReturnsOnlyActive() throws {
        let p1 = try service.addPrinciple(text: "Be kind")
        _ = try service.addPrinciple(text: "Be brave")
        try service.setState(id: p1.id!, state: .archived)

        let active = try service.listPrinciples(state: .active)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].text, "Be brave")
    }

    func testListPrinciplesActiveEmptyDb() throws {
        let active = try service.listPrinciples(state: .active)
        XCTAssertTrue(active.isEmpty)
    }

    func testListPrinciplesFilterCoverage() throws {
        let p1 = try service.addPrinciple(text: "one")
        let p2 = try service.addPrinciple(text: "two")
        let p3 = try service.addPrinciple(text: "three")
        try service.setState(id: p2.id!, state: .archived)

        let active = try service.listPrinciples(state: .active)
        XCTAssertEqual(active.map { $0.id }, [p1.id, p3.id])

        let archived = try service.listPrinciples(state: .archived)
        XCTAssertEqual(archived.map { $0.id }, [p2.id])

        let all = try service.listPrinciples(state: nil)
        XCTAssertEqual(all.map { $0.id }, [p1.id, p2.id, p3.id],
                       "listPrinciples(nil) should return all rows ordered by createdAt.asc")
    }

    // MARK: - setState

    func testSetStateSetsArchived() throws {
        let p = try service.addPrinciple(text: "Be bold")
        try service.setState(id: p.id!, state: .archived)

        let all = try dbQueue.read { db in
            try Principle.fetchAll(db)
        }
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].state, .archived)
    }

    func testSetStateRoundTrip() throws {
        let p = try service.addPrinciple(text: "Round trip")
        XCTAssertEqual(p.state, .active)

        try service.setState(id: p.id!, state: .archived)
        var fetched = try dbQueue.read { db in try Principle.fetchOne(db, key: p.id!) }
        XCTAssertEqual(fetched?.state, .archived)

        try service.setState(id: p.id!, state: .active)
        fetched = try dbQueue.read { db in try Principle.fetchOne(db, key: p.id!) }
        XCTAssertEqual(fetched?.state, .active)
    }

    // MARK: - updatePrinciple

    func testUpdatePrincipleChangesText() throws {
        let p = try service.addPrinciple(text: "Original")
        try service.updatePrinciple(id: p.id!, text: "Revised")

        let fetched = try dbQueue.read { db in try Principle.fetchOne(db, key: p.id!) }
        XCTAssertEqual(fetched?.text, "Revised")
    }

    func testUpdatePrincipleDoesNotTouchLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Test")
        _ = try service.insertQuestion(principleId: p.id!, content: "Q?")
        let before = try dbQueue.read { db in try Principle.fetchOne(db, key: p.id!) }?.lastAskedAt
        XCTAssertNotNil(before)

        try service.updatePrinciple(id: p.id!, text: "Edited")

        let after = try dbQueue.read { db in try Principle.fetchOne(db, key: p.id!) }?.lastAskedAt
        XCTAssertEqual(after, before, "Editing text must not reset the scheduler pointer")
    }

    // MARK: - pickTodaysPrinciple

    func testPickReturnsOldestLastAskedAt() throws {
        let p1 = try service.addPrinciple(text: "First")
        let p2 = try service.addPrinciple(text: "Second")

        _ = try service.insertQuestion(principleId: p1.id!, content: "Q1")

        let picked = try service.pickTodaysPrinciple()
        XCTAssertEqual(picked?.id, p2.id, "Should pick the one never asked (NULL lastAskedAt)")
    }

    func testPickReturnsOldestOfMultipleNonNull() throws {
        let p1 = try service.addPrinciple(text: "First")
        let p2 = try service.addPrinciple(text: "Second")
        let p3 = try service.addPrinciple(text: "Third")

        let now = Date()
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [now.addingTimeInterval(-300), p1.id!]
            )
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [now.addingTimeInterval(-600), p2.id!]
            )
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [now.addingTimeInterval(-100), p3.id!]
            )
        }

        let picked = try service.pickTodaysPrinciple()
        XCTAssertEqual(picked?.id, p2.id, "Should pick the principle with the oldest lastAskedAt")
    }

    func testPickReturnsSingleActivePrinciple() throws {
        let p = try service.addPrinciple(text: "Only one")
        let picked = try service.pickTodaysPrinciple()
        XCTAssertEqual(picked?.id, p.id)
    }

    func testPickReturnsNilWhenNoActivePrinciples() throws {
        let picked = try service.pickTodaysPrinciple()
        XCTAssertNil(picked)
    }

    func testPickWithAllNullLastAskedAt() throws {
        _ = try service.addPrinciple(text: "A")
        _ = try service.addPrinciple(text: "B")
        _ = try service.addPrinciple(text: "C")

        let picked = try service.pickTodaysPrinciple()
        XCTAssertNotNil(picked, "Should pick one even when all have NULL lastAskedAt")
    }

    func testPickSkipsArchivedPrinciples() throws {
        let p1 = try service.addPrinciple(text: "Archived")
        let p2 = try service.addPrinciple(text: "Active")
        try service.setState(id: p1.id!, state: .archived)

        let picked = try service.pickTodaysPrinciple()
        XCTAssertEqual(picked?.id, p2.id)
    }

    // MARK: - todaysQuestion

    func testTodaysQuestionReturnsQuestionFromToday() throws {
        let p = try service.addPrinciple(text: "Test")
        let q = try service.insertQuestion(principleId: p.id!, content: "How does this show up?")

        let todays = try service.todaysQuestion()
        XCTAssertNotNil(todays)
        XCTAssertEqual(todays?.id, q.id)
        XCTAssertEqual(todays?.content, "How does this show up?")
    }

    func testTodaysQuestionReturnsNilWhenNoQuestion() throws {
        let todays = try service.todaysQuestion()
        XCTAssertNil(todays)
    }

    // MARK: - insertQuestion

    func testInsertQuestionUpdatesLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Test")
        XCTAssertNil(p.lastAskedAt)

        _ = try service.insertQuestion(principleId: p.id!, content: "Q?")

        let updated = try dbQueue.read { db in
            try Principle.fetchOne(db, key: p.id!)
        }
        XCTAssertNotNil(updated?.lastAskedAt)
    }

    func testInsertQuestionCreatesEntryWithCorrectKind() throws {
        let p = try service.addPrinciple(text: "Test")
        let q = try service.insertQuestion(principleId: p.id!, content: "Q?")
        XCTAssertEqual(q.kind, .question)
        XCTAssertEqual(q.principleId, p.id!)
    }

    // MARK: - insertAnswer

    func testInsertAnswerCreatesEntryWithCorrectKind() throws {
        let p = try service.addPrinciple(text: "Test")
        let a = try service.insertAnswer(principleId: p.id!, content: "My answer")
        XCTAssertEqual(a.kind, .answer)
        XCTAssertEqual(a.principleId, p.id!)
    }

    func testInsertAnswerDoesNotUpdateLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Test")
        _ = try service.insertAnswer(principleId: p.id!, content: "Answer")

        let updated = try dbQueue.read { db in
            try Principle.fetchOne(db, key: p.id!)
        }
        XCTAssertNil(updated?.lastAskedAt)
    }

    // MARK: - exportAll

    func testExportAllReturnsValidJSON() throws {
        let p = try service.addPrinciple(text: "Export test")
        _ = try service.insertQuestion(principleId: p.id!, content: "Q?")
        _ = try service.insertAnswer(principleId: p.id!, content: "A.")

        let data = try service.exportAll()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["exportedAt"])
        let principles = json["principles"] as! [[String: Any]]
        let entries = json["entries"] as! [[String: Any]]
        XCTAssertEqual(principles.count, 1)
        XCTAssertEqual(entries.count, 2)
    }

    func testExportAllEmptyDb() throws {
        let data = try service.exportAll()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let principles = json["principles"] as! [Any]
        let entries = json["entries"] as! [Any]
        XCTAssertTrue(principles.isEmpty)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - findPrinciple

    func testFindPrincipleReturnsPrinciple() throws {
        let p = try service.addPrinciple(text: "Find me")
        let found = try service.findPrinciple(id: p.id!)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, p.id)
        XCTAssertEqual(found?.text, "Find me")
    }

    func testFindPrincipleReturnsNilWhenMissing() throws {
        let found = try service.findPrinciple(id: 9999)
        XCTAssertNil(found)
    }

    // MARK: - recentEntries

    func testRecentEntriesFiltersByPrincipleAndSinceOrderedAscending() throws {
        let p1 = try service.addPrinciple(text: "One")
        let p2 = try service.addPrinciple(text: "Two")

        let now = Date()
        let veryOld = now.addingTimeInterval(-60 * 60 * 24 * 45) // 45 days ago
        let cutoff = now.addingTimeInterval(-60 * 60 * 24 * 30) // 30 days ago

        try dbQueue.write { db in
            try Entry(principleId: p1.id!, kind: .question, content: "old p1 Q", createdAt: veryOld)
                .insert(db)
            try Entry(principleId: p1.id!, kind: .question, content: "fresh p1 Q",
                      createdAt: now.addingTimeInterval(-60 * 60 * 24 * 3))
                .insert(db)
            try Entry(principleId: p1.id!, kind: .answer, content: "fresh p1 A",
                      createdAt: now.addingTimeInterval(-60 * 60 * 24 * 2))
                .insert(db)
            try Entry(principleId: p2.id!, kind: .question, content: "p2 Q",
                      createdAt: now.addingTimeInterval(-60 * 60 * 24 * 1))
                .insert(db)
        }

        let entries = try service.recentEntries(principleId: p1.id!, since: cutoff)
        XCTAssertEqual(entries.map(\.content), ["fresh p1 Q", "fresh p1 A"])
    }

    func testRecentEntriesEmptyWhenPrincipleHasNoEntries() throws {
        let p = try service.addPrinciple(text: "Solo")
        let entries = try service.recentEntries(principleId: p.id!, since: Date.distantPast)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - lastQuestionBodies

    func testLastQuestionBodiesReturnsNewestNOnlyQuestions() throws {
        let p = try service.addPrinciple(text: "Test")
        // three questions across time, plus an answer in between
        let now = Date()
        try dbQueue.write { db in
            try Entry(principleId: p.id!, kind: .question, content: "q-oldest",
                      createdAt: now.addingTimeInterval(-300))
                .insert(db)
            try Entry(principleId: p.id!, kind: .answer, content: "a-should-be-ignored",
                      createdAt: now.addingTimeInterval(-250))
                .insert(db)
            try Entry(principleId: p.id!, kind: .question, content: "q-middle",
                      createdAt: now.addingTimeInterval(-200))
                .insert(db)
            try Entry(principleId: p.id!, kind: .question, content: "q-newest",
                      createdAt: now.addingTimeInterval(-100))
                .insert(db)
        }

        let bodies = try service.lastQuestionBodies(principleId: p.id!, limit: 2)
        XCTAssertEqual(bodies, ["q-newest", "q-middle"])
    }

    func testLastQuestionBodiesEmptyWhenNoQuestions() throws {
        let p = try service.addPrinciple(text: "None")
        let bodies = try service.lastQuestionBodies(principleId: p.id!, limit: 2)
        XCTAssertTrue(bodies.isEmpty)
    }

    // MARK: - hasAnsweredToday

    func testHasAnsweredTodayTrueWhenAnswerExists() throws {
        let p = try service.addPrinciple(text: "Test")
        _ = try service.insertAnswer(principleId: p.id!, content: "today's answer")
        XCTAssertTrue(try service.hasAnsweredToday())
    }

    func testHasAnsweredTodayFalseWhenNoAnswer() throws {
        _ = try service.addPrinciple(text: "Test")
        XCTAssertFalse(try service.hasAnsweredToday())
    }

    func testHasAnsweredTodayFalseWhenOnlyYesterdaysAnswer() throws {
        let p = try service.addPrinciple(text: "Test")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try dbQueue.write { db in
            try Entry(principleId: p.id!, kind: .answer, content: "yesterday",
                      createdAt: yesterday)
                .insert(db)
        }
        XCTAssertFalse(try service.hasAnsweredToday())
    }

    func testHasAnsweredTodayFalseWhenOnlyQuestionToday() throws {
        let p = try service.addPrinciple(text: "Test")
        _ = try service.insertQuestion(principleId: p.id!, content: "Q?")
        XCTAssertFalse(try service.hasAnsweredToday(),
                       "question-only today must not count as answered")
    }

    func testExportAllRoundTripsViaCodable() throws {
        let p = try service.addPrinciple(text: "Roundtrip")
        _ = try service.insertQuestion(principleId: p.id!, content: "Q?")
        _ = try service.insertAnswer(principleId: p.id!, content: "A.")

        let data = try service.exportAll()

        struct DecodedExport: Decodable {
            let exportedAt: Date
            let principles: [Principle]
            let entries: [Entry]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DecodedExport.self, from: data)

        XCTAssertEqual(decoded.principles.count, 1)
        XCTAssertEqual(decoded.principles[0].text, "Roundtrip")
        XCTAssertEqual(decoded.principles[0].state, .active)
        XCTAssertEqual(decoded.entries.count, 2)
        XCTAssertEqual(decoded.entries.map { $0.kind }.sorted { $0.rawValue < $1.rawValue }, [.answer, .question])
    }
}
