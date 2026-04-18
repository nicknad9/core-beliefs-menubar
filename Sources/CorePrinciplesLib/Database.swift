import Foundation
import GRDB

public struct AppDatabase {
    public let dbQueue: DatabaseQueue

    public init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("com.coreprinciples.app")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("principles.db").path
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("001-create-tables") { db in
            try db.create(table: "principles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("state", .text).notNull().defaults(to: "active")
                t.column("createdAt", .datetime).notNull()
                t.column("lastAskedAt", .datetime)
            }

            try db.create(table: "entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("principleId", .integer).notNull()
                    .references("principles", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_entries_principle_created",
                on: "entries",
                columns: ["principleId", "createdAt"]
            )
        }

        try migrator.migrate(dbQueue)
    }
}
