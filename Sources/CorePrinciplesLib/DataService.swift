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

    public func listActivePrinciples() throws -> [Principle] {
        try dbQueue.read { db in
            try Principle
                .filter(Column("state") == PrincipleState.active)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func addPrinciple(text: String) throws -> Principle {
        try dbQueue.write { db in
            try Principle(text: text).inserted(db)
        }
    }

    public func archivePrinciple(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE principles SET state = ? WHERE id = ?",
                arguments: [PrincipleState.archived, id]
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
}

struct ExportPayload: Codable {
    let exportedAt: Date
    let principles: [Principle]
    let entries: [Entry]
}
