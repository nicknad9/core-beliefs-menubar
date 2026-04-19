import Foundation
import GRDB

public class DataService {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func pickTodaysPrinciple() throws -> Principle? {
        try dbQueue.read { db in
            try Principle
                .filter(Column("state") == PrincipleState.active)
                .order(sql: "lastAskedAt IS NOT NULL, lastAskedAt ASC")
                .fetchOne(db)
        }
    }

    public func todaysQuestion() throws -> Entry? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return nil
        }

        return try dbQueue.read { db in
            try Entry
                .filter(Column("kind") == EntryKind.question)
                .filter(Column("createdAt") >= startOfToday && Column("createdAt") < startOfTomorrow)
                .fetchOne(db)
        }
    }

    public func insertQuestion(principleId: Int64, content: String) throws -> Entry {
        try dbQueue.write { db in
            let entry = try Entry(principleId: principleId, kind: .question, content: content)
                .inserted(db)

            try db.execute(
                sql: "UPDATE principles SET lastAskedAt = ? WHERE id = ?",
                arguments: [Date(), principleId]
            )

            return entry
        }
    }

    public func insertAnswer(principleId: Int64, content: String) throws -> Entry {
        try dbQueue.write { db in
            try Entry(principleId: principleId, kind: .answer, content: content)
                .inserted(db)
        }
    }

    public func listPrinciples(state: PrincipleState?) throws -> [Principle] {
        try dbQueue.read { db in
            let request = Principle.order(Column("createdAt").asc)
            if let state = state {
                return try request.filter(Column("state") == state).fetchAll(db)
            }
            return try request.fetchAll(db)
        }
    }

    public func addPrinciple(text: String) throws -> Principle {
        try dbQueue.write { db in
            try Principle(text: text).inserted(db)
        }
    }

    public func updatePrinciple(id: Int64, text: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET text = ? WHERE id = ?",
                arguments: [text, id]
            )
        }
    }

    public func setState(id: Int64, state: PrincipleState) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET state = ? WHERE id = ?",
                arguments: [state, id]
            )
        }
    }

    public func exportAll() throws -> Data {
        try dbQueue.read { db in
            let payload = ExportPayload(
                exportedAt: Date(),
                principles: try Principle.fetchAll(db),
                entries: try Entry.fetchAll(db)
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(payload)
        }
    }

    public func findPrinciple(id: Int64) throws -> Principle? {
        try dbQueue.read { db in
            try Principle.fetchOne(db, key: id)
        }
    }

    public func recentEntries(principleId: Int64, since: Date) throws -> [Entry] {
        try dbQueue.read { db in
            try Entry
                .filter(Column("principleId") == principleId)
                .filter(Column("createdAt") >= since)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func lastQuestionBodies(principleId: Int64, limit: Int) throws -> [String] {
        try dbQueue.read { db in
            try Entry
                .filter(Column("principleId") == principleId)
                .filter(Column("kind") == EntryKind.question)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
                .map(\.content)
        }
    }

    public func hasAnsweredToday() throws -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return false
        }
        return try dbQueue.read { db in
            try Entry
                .filter(Column("kind") == EntryKind.answer)
                .filter(Column("createdAt") >= startOfToday && Column("createdAt") < startOfTomorrow)
                .fetchCount(db) > 0
        }
    }

    public func todaysAnswer() throws -> Entry? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return nil
        }
        return try dbQueue.read { db in
            try Entry
                .filter(Column("kind") == EntryKind.answer)
                .filter(Column("createdAt") >= startOfToday && Column("createdAt") < startOfTomorrow)
                .order(Column("createdAt").desc)
                .fetchOne(db)
        }
    }
}

struct ExportPayload: Codable {
    let exportedAt: Date
    let principles: [Principle]
    let entries: [Entry]
}
