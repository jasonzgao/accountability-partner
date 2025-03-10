import Foundation
import GRDB

/// Manages the SQLite database for the Productivity Assistant application
final class DatabaseManager {
    // MARK: - Properties
    
    /// Shared singleton instance
    static let shared = DatabaseManager()
    
    /// The database connection pool
    private(set) var dbPool: DatabasePool?
    
    /// Path to the SQLite database file
    private let databaseURL: URL
    
    // MARK: - Initialization
    
    private init() {
        // Create a URL for the database in the application support directory
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderURL = applicationSupportURL.appendingPathComponent("ProductivityAssistant", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        
        // Set the database URL
        databaseURL = appFolderURL.appendingPathComponent("productivity_assistant.sqlite")
    }
    
    // MARK: - Public Methods
    
    /// Sets up the database connection and runs migrations
    func setup() throws {
        // Create the database pool
        dbPool = try DatabasePool(path: databaseURL.path)
        
        // Run migrations
        try runMigrations()
    }
    
    /// Executes a database operation in a write transaction
    func write<T>(_ operation: @escaping (Database) throws -> T) throws -> T {
        guard let dbPool = dbPool else {
            throw DatabaseError.databaseNotInitialized
        }
        
        return try dbPool.write(operation)
    }
    
    /// Executes a database operation in a read transaction
    func read<T>(_ operation: @escaping (Database) throws -> T) throws -> T {
        guard let dbPool = dbPool else {
            throw DatabaseError.databaseNotInitialized
        }
        
        return try dbPool.read(operation)
    }
    
    // MARK: - Private Methods
    
    /// Runs all database migrations
    private func runMigrations() throws {
        guard let dbPool = dbPool else {
            throw DatabaseError.databaseNotInitialized
        }
        
        // Create migrations
        var migrator = DatabaseMigrator()
        
        // Initial migration - creates tables
        migrator.registerMigration("createTables") { db in
            // Activity Records table
            try db.create(table: "activity_records") { table in
                table.column("id", .text).primaryKey().notNull()
                table.column("start_time", .datetime).notNull()
                table.column("end_time", .datetime)
                table.column("application_type", .text).notNull()
                table.column("application_name", .text).notNull()
                table.column("window_title", .text)
                table.column("url", .text)
                table.column("category", .text).notNull()
                
                table.index(["start_time", "end_time"])
                table.index(["application_name"])
                table.index(["category"])
            }
            
            // Activity Categories table for custom categories
            try db.create(table: "activity_categories") { table in
                table.column("id", .text).primaryKey().notNull()
                table.column("name", .text).notNull()
                table.column("type", .text).notNull() // productive, neutral, distracting
                table.column("color", .text)
                
                table.index(["type"])
            }
            
            // Category Rules table
            try db.create(table: "category_rules") { table in
                table.column("id", .text).primaryKey().notNull()
                table.column("application_name", .text)
                table.column("url_pattern", .text)
                table.column("window_title_pattern", .text)
                table.column("category_id", .text).notNull()
                    .references("activity_categories", onDelete: .cascade)
                
                table.index(["application_name"])
                table.index(["category_id"])
            }
        }
        
        // Run migrations
        try migrator.migrate(dbPool)
    }
}

/// Database-related errors
enum DatabaseError: Error {
    case databaseNotInitialized
    case migrationFailed(String)
    case operationFailed(String)
} 