import Foundation
import GRDB

public enum PrincipleState: String, Codable {
    case active
    case archived
}

extension PrincipleState: DatabaseValueConvertible {}

public enum EntryKind: String, Codable {
    case question
    case answer
}

extension EntryKind: DatabaseValueConvertible {}

public struct Principle: Codable, FetchableRecord, PersistableRecord, Identifiable {
    public static let databaseTableName = "principles"

    public var id: Int64?
    public var text: String
    public var state: PrincipleState
    public var createdAt: Date
    public var lastAskedAt: Date?

    public init(text: String, state: PrincipleState = .active, createdAt: Date = Date(), lastAskedAt: Date? = nil) {
        self.text = text
        self.state = state
        self.createdAt = createdAt
        self.lastAskedAt = lastAskedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable {
    public static let databaseTableName = "entries"

    public var id: Int64?
    public var principleId: Int64
    public var kind: EntryKind
    public var content: String
    public var createdAt: Date

    public init(principleId: Int64, kind: EntryKind, content: String, createdAt: Date = Date()) {
        self.principleId = principleId
        self.kind = kind
        self.content = content
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
