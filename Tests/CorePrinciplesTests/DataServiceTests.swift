import XCTest
import GRDB
@testable import CorePrinciplesLib

final class DataServiceTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var service: DataService!

    override func setUpWithError() throws {
        dbQueue = try DatabaseQueue()
        let _ = try AppDatabase(dbQueue: dbQueue)
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
        let _ = try AppDatabase(dbQueue: dbQueue)
        try dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("principles"))
        }
    }

    // MARK: - addPrinciple

    func testAddPrincipleCreatesActive() throws {
        let p = try service.addPrinciple(text: "Be patient")
        XCTAssertNotNil(p.id)
        XCTAssertEqual(p.text, "Be patient")
        XCTAssertEqual(p.state, "active")
        XCTAssertNil(p.lastAskedAt)
    }

    // MARK: - listActivePrinciples

    func testListActivePrinciplesReturnsOnlyActive() throws {
        let p1 = try service.addPrinciple(text: "Be kind")
        let _ = try service.addPrinciple(text: "Be brave")
        try service.archivePrinciple(id: p1.id!)

        let active = try service.listActivePrinciples()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].text, "Be brave")
    }

    func testListActivePrinciplesEmptyDb() throws {
        let active = try service.listActivePrinciples()
        XCTAssertTrue(active.isEmpty)
    }

    // MARK: - archivePrinciple

    func testArchiveSetsStateArchived() throws {
        let p = try service.addPrinciple(text: "Be bold")
        try service.archivePrinciple(id: p.id!)

        let all = try dbQueue.read { db in
            try Principle.fetchAll(db)
        }
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].state, "archived")
    }

    // MARK: - pickTodaysPrinciple

    func testPickReturnsOldestLastAskedAt() throws {
        let p1 = try service.addPrinciple(text: "First")
        let p2 = try service.addPrinciple(text: "Second")

        let _ = try service.insertQuestion(principleId: p1.id!, content: "Q1")

        let picked = try service.pickTodaysPrinciple()
        XCTAssertEqual(picked?.id, p2.id, "Should pick the one never asked (NULL lastAskedAt)")
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
        let _ = try service.addPrinciple(text: "A")
        let _ = try service.addPrinciple(text: "B")
        let _ = try service.addPrinciple(text: "C")

        let picked = try service.pickTodaysPrinciple()
        XCTAssertNotNil(picked, "Should pick one even when all have NULL lastAskedAt")
    }

    func testPickSkipsArchivedPrinciples() throws {
        let p1 = try service.addPrinciple(text: "Archived")
        let p2 = try service.addPrinciple(text: "Active")
        try service.archivePrinciple(id: p1.id!)

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

        let _ = try service.insertQuestion(principleId: p.id!, content: "Q?")

        let updated = try dbQueue.read { db in
            try Principle.fetchOne(db, key: p.id!)
        }
        XCTAssertNotNil(updated?.lastAskedAt)
    }

    func testInsertQuestionCreatesEntryWithCorrectKind() throws {
        let p = try service.addPrinciple(text: "Test")
        let q = try service.insertQuestion(principleId: p.id!, content: "Q?")
        XCTAssertEqual(q.kind, "question")
        XCTAssertEqual(q.principleId, p.id!)
    }

    // MARK: - insertAnswer

    func testInsertAnswerCreatesEntryWithCorrectKind() throws {
        let p = try service.addPrinciple(text: "Test")
        let a = try service.insertAnswer(principleId: p.id!, content: "My answer")
        XCTAssertEqual(a.kind, "answer")
        XCTAssertEqual(a.principleId, p.id!)
    }

    func testInsertAnswerDoesNotUpdateLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Test")
        let _ = try service.insertAnswer(principleId: p.id!, content: "Answer")

        let updated = try dbQueue.read { db in
            try Principle.fetchOne(db, key: p.id!)
        }
        XCTAssertNil(updated?.lastAskedAt)
    }

    // MARK: - exportAll

    func testExportAllReturnsValidJSON() throws {
        let p = try service.addPrinciple(text: "Export test")
        let _ = try service.insertQuestion(principleId: p.id!, content: "Q?")
        let _ = try service.insertAnswer(principleId: p.id!, content: "A.")

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
}
