import XCTest
import GRDB
@testable import CorePrinciplesLib

final class DailyQuestionSchedulerTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var service: DataService!

    override func setUpWithError() throws {
        dbQueue = try DatabaseQueue()
        _ = try AppDatabase(dbQueue: dbQueue)
        service = DataService(dbQueue: dbQueue)
    }

    // Synchronous fake generator — returns either a stub string or throws.
    private struct FakeGenerator: QuestionGenerator {
        let result: Result<String, Error>
        var callCount: CallCounter = CallCounter()

        func generate(prompt: String) throws -> String {
            callCount.increment()
            switch result {
            case .success(let text): return text
            case .failure(let error): throw error
            }
        }
    }

    private final class CallCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private struct FakeError: Error, Equatable { let tag: String }

    private func runSync(_ scheduler: DailyQuestionScheduler) -> SchedulerOutcome {
        let exp = expectation(description: "scheduler callback")
        var captured: SchedulerOutcome!
        scheduler.today { outcome in
            captured = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        return captured
    }

    private func makeScheduler(generator: QuestionGenerator) -> DailyQuestionScheduler {
        // Use a non-main completion queue so XCTest expectation completes without runloop drama.
        DailyQuestionScheduler(
            dataService: service,
            generator: generator,
            completionQueue: DispatchQueue(label: "test.completion")
        )
    }

    // MARK: - Existing question path

    func test_returnsReady_whenTodayAlreadyHasQuestion() throws {
        let p = try service.addPrinciple(text: "Seeded")
        let q = try service.insertQuestion(principleId: p.id!, content: "seeded Q")
        let gen = FakeGenerator(result: .success("should-not-be-called"))

        let outcome = runSync(makeScheduler(generator: gen))

        if case let .ready(principle, question, alreadyAnswered) = outcome {
            XCTAssertEqual(principle.id, p.id)
            XCTAssertEqual(question.id, q.id)
            XCTAssertFalse(alreadyAnswered)
        } else {
            XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(gen.callCount.value, 0, "must NOT call generator when today already has a question")
    }

    func test_returnsReady_withAlreadyAnsweredTrue_whenTodayHasAnswer() throws {
        let p = try service.addPrinciple(text: "Seeded")
        _ = try service.insertQuestion(principleId: p.id!, content: "seeded Q")
        _ = try service.insertAnswer(principleId: p.id!, content: "my answer")
        let gen = FakeGenerator(result: .success("unused"))

        let outcome = runSync(makeScheduler(generator: gen))

        if case let .ready(_, _, alreadyAnswered) = outcome {
            XCTAssertTrue(alreadyAnswered)
        } else {
            XCTFail("expected .ready, got \(outcome)")
        }
    }

    // MARK: - Generation path

    func test_picksOldestLastAskedAt_amongActive() throws {
        let newer = try service.addPrinciple(text: "Newer")
        let older = try service.addPrinciple(text: "Older")
        let archived = try service.addPrinciple(text: "Archived")

        let now = Date()
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [now.addingTimeInterval(-100), newer.id!]
            )
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [now.addingTimeInterval(-1000), older.id!]
            )
        }
        try service.setState(id: archived.id!, state: .archived)

        let gen = FakeGenerator(result: .success("generated for older"))
        let outcome = runSync(makeScheduler(generator: gen))

        if case let .ready(picked, question, alreadyAnswered) = outcome {
            XCTAssertEqual(picked.id, older.id, "must pick the principle with the oldest lastAskedAt among active")
            XCTAssertEqual(question.content, "generated for older")
            XCTAssertFalse(alreadyAnswered)
        } else {
            XCTFail("expected .ready, got \(outcome)")
        }
    }

    func test_onSuccess_insertsQuestion_andAdvancesLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Target")
        XCTAssertNil(p.lastAskedAt)

        let gen = FakeGenerator(result: .success("fresh question"))
        _ = runSync(makeScheduler(generator: gen))

        XCTAssertNotNil(try service.todaysQuestion(), "question row must be inserted")
        let updated = try service.findPrinciple(id: p.id!)
        XCTAssertNotNil(updated?.lastAskedAt, "lastAskedAt must advance on successful generation")
    }

    // THE hard rule per design doc §177.
    func test_onGeneratorFailure_doesNotInsertQuestion_andDoesNotAdvanceLastAskedAt() throws {
        let p = try service.addPrinciple(text: "Flaky")
        let originalLastAsked = Date(timeIntervalSince1970: 1_700_000_000)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [originalLastAsked, p.id!]
            )
        }

        let gen = FakeGenerator(result: .failure(FakeError(tag: "network down")))
        let outcome = runSync(makeScheduler(generator: gen))

        if case .failed(let err) = outcome {
            XCTAssertEqual((err as? FakeError)?.tag, "network down")
        } else {
            XCTFail("expected .failed, got \(outcome)")
        }

        XCTAssertNil(try service.todaysQuestion(), "NO question row may be inserted on generator failure")

        let after = try service.findPrinciple(id: p.id!)
        let lastAskedAfter = try XCTUnwrap(after?.lastAskedAt, "lastAskedAt was wiped out entirely")
        XCTAssertEqual(
            lastAskedAfter.timeIntervalSince1970,
            originalLastAsked.timeIntervalSince1970,
            accuracy: 0.001,
            "lastAskedAt must not advance on generator failure"
        )
    }

    func test_returnsEmpty_whenNoActivePrinciples() throws {
        let gen = FakeGenerator(result: .success("unused"))
        let outcome = runSync(makeScheduler(generator: gen))

        if case .empty = outcome { /* ok */ } else {
            XCTFail("expected .empty for zero-principle DB, got \(outcome)")
        }
        XCTAssertEqual(gen.callCount.value, 0, "must not call generator when no active principles")
    }

    func test_returnsEmpty_whenOnlyArchivedPrinciples() throws {
        let p = try service.addPrinciple(text: "Archived only")
        try service.setState(id: p.id!, state: .archived)

        let gen = FakeGenerator(result: .success("unused"))
        let outcome = runSync(makeScheduler(generator: gen))

        if case .empty = outcome { /* ok */ } else {
            XCTFail("expected .empty, got \(outcome)")
        }
    }
}
