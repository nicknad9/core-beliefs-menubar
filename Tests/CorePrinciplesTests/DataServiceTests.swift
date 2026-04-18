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
