import Foundation
import GRDB
import Combine
import os.log

/// Protocol for interacting with goal data
protocol GoalRepositoryProtocol {
    /// Gets all goals
    func getAllGoals() throws -> [Goal]
    
    /// Gets all active goals
    func getActiveGoals() throws -> [Goal]
    
    /// Gets a specific goal by ID
    func getGoal(id: String) throws -> Goal?
    
    /// Saves a goal
    func saveGoal(_ goal: Goal) throws
    
    /// Deletes a goal
    func deleteGoal(id: String) throws
    
    /// Updates a goal's progress
    func updateGoalProgress(id: String, progress: Double) throws
    
    /// Get progress history for a goal
    func getGoalProgressHistory(goalId: String) throws -> [GoalProgressRecord]
    
    /// Save a progress record
    func saveProgressRecord(_ record: GoalProgressRecord) throws
    
    /// Get goals by filter
    func getGoals(matching filter: GoalFilter) throws -> [Goal]
    
    /// Publisher for goals
    var goalsPublisher: AnyPublisher<[Goal], Error> { get }
}

/// Filter options for querying goals
struct GoalFilter {
    var isActive: Bool?
    var type: GoalType?
    var frequency: GoalFrequency?
    var isCompleted: Bool?
    var isArchived: Bool?
    var categoryId: String?
    var applicationName: String?
    var containsUrl: String?
    
    init(
        isActive: Bool? = nil,
        type: GoalType? = nil,
        frequency: GoalFrequency? = nil,
        isCompleted: Bool? = nil,
        isArchived: Bool? = nil,
        categoryId: String? = nil,
        applicationName: String? = nil,
        containsUrl: String? = nil
    ) {
        self.isActive = isActive
        self.type = type
        self.frequency = frequency
        self.isCompleted = isCompleted
        self.isArchived = isArchived
        self.categoryId = categoryId
        self.applicationName = applicationName
        self.containsUrl = containsUrl
    }
}

/// Repository for managing goal data
class GoalRepository: GoalRepositoryProtocol {
    private let logger = Logger(subsystem: "com.productivityassistant", category: "GoalRepository")
    private let database: DatabaseQueue
    private let goalSubject = PassthroughSubject<[Goal], Error>()
    
    var goalsPublisher: AnyPublisher<[Goal], Error> {
        return goalSubject.eraseToAnyPublisher()
    }
    
    init(database: DatabaseQueue = DatabaseManager.shared.database) {
        self.database = database
        
        do {
            try createTablesIfNeeded()
        } catch {
            logger.error("Failed to create goal tables: \(error.localizedDescription)")
        }
    }
    
    private func createTablesIfNeeded() throws {
        try database.write { db in
            // Create goals table if it doesn't exist
            try db.create(table: "goals", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("type", .text).notNull()
                t.column("frequency", .text).notNull()
                t.column("target", .double).notNull()
                t.column("currentProgress", .double).notNull()
                t.column("unit", .text).notNull()
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime)
                t.column("categoryFilter", .text)
                t.column("applicationFilter", .text)
                t.column("urlFilter", .text)
                t.column("lastUpdated", .datetime).notNull()
                t.column("isActive", .boolean).notNull()
                t.column("daysCompleted", .integer).notNull()
                t.column("streak", .integer).notNull()
                t.column("customFrequencyDays", .text)
                t.column("reminderTime", .datetime)
                t.column("isArchived", .boolean).notNull()
            }
            
            // Create goal progress table if it doesn't exist
            try db.create(table: "goal_progress", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("goalId", .text).notNull().indexed()
                    .references("goals", column: "id", onDelete: .cascade)
                t.column("date", .datetime).notNull().indexed()
                t.column("progressValue", .double).notNull()
                t.column("isCompleted", .boolean).notNull()
            }
        }
    }
    
    // MARK: - Implementation of GoalRepositoryProtocol
    
    func getAllGoals() throws -> [Goal] {
        return try database.read { db in
            try GoalRecord.fetchAll(db).map { $0.toModel() }
        }
    }
    
    func getActiveGoals() throws -> [Goal] {
        return try database.read { db in
            try GoalRecord
                .filter(Column("isActive") == true)
                .filter(Column("isArchived") == false)
                .fetchAll(db)
                .map { $0.toModel() }
        }
    }
    
    func getGoal(id: String) throws -> Goal? {
        return try database.read { db in
            try GoalRecord
                .filter(Column("id") == id)
                .fetchOne(db)?
                .toModel()
        }
    }
    
    func saveGoal(_ goal: Goal) throws {
        try database.write { db in
            let record = GoalRecord(from: goal)
            try record.save(db)
        }
        
        // Notify subscribers
        refreshGoalsPublisher()
    }
    
    func deleteGoal(id: String) throws {
        try database.write { db in
            _ = try GoalRecord.deleteOne(db, key: id)
        }
        
        // Notify subscribers
        refreshGoalsPublisher()
    }
    
    func updateGoalProgress(id: String, progress: Double) throws {
        try database.write { db in
            if var goal = try GoalRecord.fetchOne(db, key: id) {
                // Convert to model and back to ensure we have the latest version
                var goalModel = goal.toModel()
                goalModel.currentProgress = progress
                goalModel.lastUpdated = Date()
                
                if goalModel.isCompleted && goalModel.currentProgress > goalModel.target {
                    goalModel.daysCompleted += 1
                    goalModel.streak += 1
                }
                
                let updatedRecord = GoalRecord(from: goalModel)
                try updatedRecord.save(db)
                
                // Create a progress record
                let progressRecord = GoalProgressRecord(
                    goalId: id,
                    progressValue: progress,
                    isCompleted: goalModel.isCompleted
                )
                try progressRecord.save(db)
            }
        }
        
        // Notify subscribers
        refreshGoalsPublisher()
    }
    
    func getGoalProgressHistory(goalId: String) throws -> [GoalProgressRecord] {
        return try database.read { db in
            try GoalProgressRecord
                .filter(Column("goalId") == goalId)
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }
    
    func saveProgressRecord(_ record: GoalProgressRecord) throws {
        try database.write { db in
            try record.save(db)
        }
    }
    
    func getGoals(matching filter: GoalFilter) throws -> [Goal] {
        return try database.read { db in
            var query = GoalRecord.all()
            
            if let isActive = filter.isActive {
                query = query.filter(Column("isActive") == isActive)
            }
            
            if let type = filter.type {
                query = query.filter(Column("type") == type.rawValue)
            }
            
            if let frequency = filter.frequency {
                query = query.filter(Column("frequency") == frequency.rawValue)
            }
            
            if let isCompleted = filter.isCompleted {
                if isCompleted {
                    query = query.filter(Column("currentProgress") >= Column("target"))
                } else {
                    query = query.filter(Column("currentProgress") < Column("target"))
                }
            }
            
            if let isArchived = filter.isArchived {
                query = query.filter(Column("isArchived") == isArchived)
            }
            
            if let categoryId = filter.categoryId {
                query = query.filter(Column("categoryFilter") == categoryId)
            }
            
            if let appName = filter.applicationName {
                query = query.filter(Column("applicationFilter").like("%\(appName)%"))
            }
            
            if let url = filter.containsUrl {
                query = query.filter(Column("urlFilter").like("%\(url)%"))
            }
            
            return try query.fetchAll(db).map { $0.toModel() }
        }
    }
    
    // MARK: - Private Methods
    
    private func refreshGoalsPublisher() {
        do {
            let goals = try getAllGoals()
            goalSubject.send(goals)
        } catch {
            logger.error("Failed to refresh goals publisher: \(error.localizedDescription)")
            goalSubject.send(completion: .failure(error))
        }
    }
} 
 