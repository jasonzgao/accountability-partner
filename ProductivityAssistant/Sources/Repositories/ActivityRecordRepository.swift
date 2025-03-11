import Foundation
import GRDB
import Combine
import os.log

/// Protocol defining the operations for managing activity records
protocol ActivityRecordRepositoryProtocol {
    /// Saves an activity record to the database
    func save(_ record: ActivityRecord) throws
    
    /// Updates an existing activity record
    func update(_ record: ActivityRecord) throws
    
    /// Deletes an activity record from the database
    func delete(id: UUID) throws
    
    /// Retrieves an activity record by its ID
    func getById(id: UUID) throws -> ActivityRecord?
    
    /// Retrieves activity records within a time range
    func getActivitiesInRange(from: Date, to: Date) throws -> [ActivityRecord]
    
    /// Retrieves activities by category
    func getActivitiesByCategory(_ category: ActivityCategory, limit: Int) throws -> [ActivityRecord]
    
    /// Retrieves activity records for a specific application
    func getActivitiesByApplication(name: String, limit: Int) throws -> [ActivityRecord]
    
    /// Retrieves the most recent activity
    func getMostRecentActivity() throws -> ActivityRecord?
    
    /// Applies the data retention policy, deleting records older than the retention period
    func applyRetentionPolicy(retentionDays: Int) throws -> Int
    
    /// Clears all activity records from the database
    func clearAllData() throws -> Int
    
    /// Publishes activity records as they are added
    var activityPublisher: AnyPublisher<ActivityRecord, Error> { get }
    
    /// Saves an activity record to the database
    func saveActivity(_ activity: ActivityRecord) throws
    
    /// Retrieves an activity record by its ID
    func getActivity(id: String) throws -> ActivityRecord?
    
    /// Retrieves activities in a range grouped by category
    func getActivitiesInRangeGroupedByCategory(from: Date, to: Date) throws -> [String: [ActivityRecord]]
    
    /// Retrieves the latest activities
    func getLatestActivities(limit: Int) throws -> [ActivityRecord]
    
    /// Retrieves the latest activities by category
    func getLatestActivityByCategory(category: ActivityCategory, limit: Int) throws -> [ActivityRecord]
    
    /// Retrieves the top applications
    func getTopApplications(from: Date, to: Date, limit: Int) throws -> [(applicationName: String, duration: TimeInterval)]
    
    /// Retrieves the top websites
    func getTopWebsites(from: Date, to: Date, limit: Int) throws -> [(host: String, duration: TimeInterval)]
    
    /// Retrieves productivity by hour
    func getProductivityByHour(from: Date, to: Date) throws -> [(hour: Int, productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)]
    
    /// Retrieves productivity by day
    func getProductivityByDay(days: Int) throws -> [(day: Date, productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)]
    
    /// Retrieves time spent by category
    func getTimeSpentByCategory(from: Date, to: Date) throws -> [(category: ActivityCategory, duration: TimeInterval)]
    
    /// Retrieves daily streak
    func getDailyStreak(category: ActivityCategory, minimumSeconds: TimeInterval) throws -> Int
    
    /// Executes a time query
    func executeTimeQuery(query: String, arguments: [DatabaseValueConvertible]) throws -> Double
    
    /// Executes a count query
    func executeCountQuery(query: String, arguments: [DatabaseValueConvertible]) throws -> Double
}

/// Implementation of the ActivityRecordRepository using GRDB
final class ActivityRecordRepository: ActivityRecordRepositoryProtocol {
    // MARK: - Properties
    
    private let databaseManager: DatabaseManager
    private let activitySubject = PassthroughSubject<ActivityRecord, Error>()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "ActivityRepository")
    
    // Cache for frequently accessed data
    private var cache = NSCache<NSString, CacheItem>()
    private let cacheQueue = DispatchQueue(label: "com.productivityassistant.activityrepo.cache")
    
    // Cache timeout in seconds
    private let cacheTimeout: TimeInterval = 60 // 1 minute
    
    var activityPublisher: AnyPublisher<ActivityRecord, Error> {
        return activitySubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.databaseManager = databaseManager
        setupCache()
    }
    
    // MARK: - Public Methods
    
    func save(_ record: ActivityRecord) throws {
        try databaseManager.write { db in
            try record.save(db)
            
            // Publish the new record
            activitySubject.send(record)
            
            // Update cache if necessary
            self.cacheQueue.async {
                self.invalidateCacheForDate(record.startTime)
            }
        }
    }
    
    func update(_ record: ActivityRecord) throws {
        try databaseManager.write { db in
            try record.update(db)
            
            // Update cache if necessary
            self.cacheQueue.async {
                self.invalidateCacheForDate(record.startTime)
                if let endTime = record.endTime {
                    self.invalidateCacheForDate(endTime)
                }
            }
        }
    }
    
    func delete(id: UUID) throws {
        try databaseManager.write { db in
            // Get the record first to invalidate cache properly
            if let record = try ActivityRecord.filter(Column("id") == id.uuidString).fetchOne(db) {
                // Delete the record
                _ = try ActivityRecord.filter(Column("id") == id.uuidString).deleteAll(db)
                
                // Invalidate cache
                self.cacheQueue.async {
                    self.invalidateCacheForDate(record.startTime)
                    if let endTime = record.endTime {
                        self.invalidateCacheForDate(endTime)
                    }
                }
            } else {
                _ = try ActivityRecord.filter(Column("id") == id.uuidString).deleteAll(db)
            }
        }
    }
    
    func getById(id: UUID) throws -> ActivityRecord? {
        // Check cache first
        let cacheKey = "id_\(id.uuidString)" as NSString
        
        if let cachedItem = getCachedItem(key: cacheKey) {
            if let record = cachedItem.value as? ActivityRecord {
                logger.debug("Cache hit for activity \(id.uuidString)")
                return record
            }
        }
        
        // If not in cache, query database
        let record = try databaseManager.read { db in
            try ActivityRecord.filter(Column("id") == id.uuidString).fetchOne(db)
        }
        
        // Add to cache if found
        if let record = record {
            cacheQueue.async {
                self.cache.setObject(CacheItem(value: record), forKey: cacheKey)
            }
        }
        
        return record
    }
    
    func getActivitiesInRange(from startDate: Date, to endDate: Date) throws -> [ActivityRecord] {
        // Check cache for this date range
        let dateFormatter = ISO8601DateFormatter()
        let cacheKey = "range_\(dateFormatter.string(from: startDate))_\(dateFormatter.string(from: endDate))" as NSString
        
        if let cachedItem = getCachedItem(key: cacheKey) {
            if let activities = cachedItem.value as? [ActivityRecord] {
                logger.debug("Cache hit for date range \(startDate) to \(endDate)")
                return activities
            }
        }
        
        // If not in cache, query database
        let activities = try databaseManager.read { db in
            try ActivityRecord
                .filter(Column("start_time") >= startDate)
                .filter(Column("start_time") <= endDate)
                .order(Column("start_time").desc)
                .fetchAll(db)
        }
        
        // Add to cache
        cacheQueue.async {
            self.cache.setObject(CacheItem(value: activities), forKey: cacheKey)
        }
        
        return activities
    }
    
    func getActivitiesByCategory(_ category: ActivityCategory, limit: Int) throws -> [ActivityRecord] {
        // Check cache
        let cacheKey = "category_\(category.rawValue)_\(limit)" as NSString
        
        if let cachedItem = getCachedItem(key: cacheKey) {
            if let activities = cachedItem.value as? [ActivityRecord] {
                logger.debug("Cache hit for category \(category.rawValue)")
                return activities
            }
        }
        
        // Query database
        let activities = try databaseManager.read { db in
            try ActivityRecord
                .filter(Column("category") == category.rawValue)
                .order(Column("start_time").desc)
                .limit(limit)
                .fetchAll(db)
        }
        
        // Add to cache
        cacheQueue.async {
            self.cache.setObject(CacheItem(value: activities), forKey: cacheKey)
        }
        
        return activities
    }
    
    func getActivitiesByApplication(name: String, limit: Int) throws -> [ActivityRecord] {
        // Check cache
        let cacheKey = "app_\(name)_\(limit)" as NSString
        
        if let cachedItem = getCachedItem(key: cacheKey) {
            if let activities = cachedItem.value as? [ActivityRecord] {
                logger.debug("Cache hit for application \(name)")
                return activities
            }
        }
        
        // Query database
        let activities = try databaseManager.read { db in
            try ActivityRecord
                .filter(Column("application_name") == name)
                .order(Column("start_time").desc)
                .limit(limit)
                .fetchAll(db)
        }
        
        // Add to cache
        cacheQueue.async {
            self.cache.setObject(CacheItem(value: activities), forKey: cacheKey)
        }
        
        return activities
    }
    
    func getMostRecentActivity() throws -> ActivityRecord? {
        // Always fetch from database to ensure most recent
        return try databaseManager.read { db in
            try ActivityRecord
                .order(Column("start_time").desc)
                .fetchOne(db)
        }
    }
    
    func applyRetentionPolicy(retentionDays: Int) throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        
        let deletedCount = try databaseManager.write { db in
            try ActivityRecord
                .filter(Column("start_time") < cutoffDate)
                .deleteAll(db)
        }
        
        // Clear cache after bulk deletion
        clearCache()
        
        logger.info("Applied retention policy: Deleted \(deletedCount) records older than \(retentionDays) days")
        
        return deletedCount
    }
    
    func clearAllData() throws -> Int {
        let deletedCount = try databaseManager.write { db in
            try ActivityRecord.deleteAll(db)
        }
        
        // Clear cache after bulk deletion
        clearCache()
        
        logger.info("Cleared all activity data: \(deletedCount) records deleted")
        
        return deletedCount
    }
    
    func saveActivity(_ activity: ActivityRecord) throws {
        try databaseManager.write { db in
            try activity.save(db)
            
            // Publish the new record
            activitySubject.send(activity)
            
            // Update cache if necessary
            self.cacheQueue.async {
                self.invalidateCacheForDate(activity.startTime)
            }
        }
    }
    
    func getActivity(id: String) throws -> ActivityRecord? {
        // Check cache first
        let cacheKey = "id_\(id)" as NSString
        
        if let cachedItem = getCachedItem(key: cacheKey) {
            if let record = cachedItem.value as? ActivityRecord {
                logger.debug("Cache hit for activity \(id)")
                return record
            }
        }
        
        // If not in cache, query database
        let record = try databaseManager.read { db in
            try ActivityRecord.filter(Column("id") == id).fetchOne(db)
        }
        
        // Add to cache if found
        if let record = record {
            cacheQueue.async {
                self.cache.setObject(CacheItem(value: record), forKey: cacheKey)
            }
        }
        
        return record
    }
    
    func getActivitiesInRangeGroupedByCategory(from startDate: Date, to endDate: Date) throws -> [String: [ActivityRecord]] {
        let activities = try getActivitiesInRange(from: startDate, to: endDate)
        var groupedActivities: [String: [ActivityRecord]] = [:]
        
        for activity in activities {
            let category = activity.category.rawValue
            if var categoryActivities = groupedActivities[category] {
                categoryActivities.append(activity)
            } else {
                groupedActivities[category] = [activity]
            }
        }
        
        return groupedActivities
    }
    
    func getLatestActivities(limit: Int) throws -> [ActivityRecord] {
        return try getActivitiesInRange(from: Date().addingTimeInterval(-86400), to: Date())
    }
    
    func getLatestActivityByCategory(category: ActivityCategory, limit: Int) throws -> [ActivityRecord] {
        return try getActivitiesByCategory(category, limit: limit)
    }
    
    func getTopApplications(from startDate: Date, to endDate: Date, limit: Int) throws -> [(applicationName: String, duration: TimeInterval)] {
        let activities = try getActivitiesInRange(from: startDate, to: endDate)
        var applicationDurations: [String: TimeInterval] = [:]
        
        for activity in activities {
            let application = activity.applicationName
            let duration = (activity.endTime ?? Date()).timeIntervalSince(activity.startTime)
            applicationDurations[application, default: 0] += duration
        }
        
        let sortedApplications = applicationDurations.sorted { $0.value > $1.value }
        return Array(sortedApplications.prefix(limit)).map { ($0.key, $0.value) }
    }
    
    func getTopWebsites(from startDate: Date, to endDate: Date, limit: Int) throws -> [(host: String, duration: TimeInterval)] {
        let activities = try getActivitiesInRange(from: startDate, to: endDate)
        var websiteDurations: [String: TimeInterval] = [:]
        
        for activity in activities {
            if let url = activity.url, let host = URL(string: url)?.host {
                let duration = (activity.endTime ?? Date()).timeIntervalSince(activity.startTime)
                websiteDurations[host, default: 0] += duration
            }
        }
        
        let sortedWebsites = websiteDurations.sorted { $0.value > $1.value }
        return Array(sortedWebsites.prefix(limit)).map { ($0.key, $0.value) }
    }
    
    func getProductivityByHour(from startDate: Date, to endDate: Date) throws -> [(hour: Int, productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)] {
        let activities = try getActivitiesInRange(from: startDate, to: endDate)
        var productivityByHour: [Int: (productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)] = [:]
        
        for activity in activities {
            let startTime = activity.startTime
            let hour = Calendar.current.component(.hour, from: startTime)
            let duration = (activity.endTime ?? Date()).timeIntervalSince(startTime)
            
            if activity.category == .productive {
                productivityByHour[hour, default: (0, 0, 0)].productive += duration
            } else if activity.category == .neutral {
                productivityByHour[hour, default: (0, 0, 0)].neutral += duration
            } else if activity.category == .distracting {
                productivityByHour[hour, default: (0, 0, 0)].distracting += duration
            }
        }
        
        return productivityByHour.map { ($0.key, $0.value.productive, $0.value.neutral, $0.value.distracting) }
    }
    
    func getProductivityByDay(days: Int) throws -> [(day: Date, productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)] {
        let activities = try getActivitiesInRange(from: Date().addingTimeInterval(-86400 * TimeInterval(days)), to: Date())
        var productivityByDay: [Date: (productive: TimeInterval, neutral: TimeInterval, distracting: TimeInterval)] = [:]
        
        for activity in activities {
            let startTime = activity.startTime
            let day = Calendar.current.startOfDay(for: startTime)
            let duration = (activity.endTime ?? Date()).timeIntervalSince(startTime)
            
            if activity.category == .productive {
                productivityByDay[day, default: (0, 0, 0)].productive += duration
            } else if activity.category == .neutral {
                productivityByDay[day, default: (0, 0, 0)].neutral += duration
            } else if activity.category == .distracting {
                productivityByDay[day, default: (0, 0, 0)].distracting += duration
            }
        }
        
        return productivityByDay.map { ($0.key, $0.value.productive, $0.value.neutral, $0.value.distracting) }
    }
    
    func getTimeSpentByCategory(from startDate: Date, to endDate: Date) throws -> [(category: ActivityCategory, duration: TimeInterval)] {
        let activities = try getActivitiesInRange(from: startDate, to: endDate)
        var timeSpentByCategory: [ActivityCategory: TimeInterval] = [:]
        
        for activity in activities {
            let category = activity.category
            let duration = (activity.endTime ?? Date()).timeIntervalSince(activity.startTime)
            timeSpentByCategory[category, default: 0] += duration
        }
        
        return timeSpentByCategory.map { ($0.key, $0.value) }
    }
    
    func getDailyStreak(category: ActivityCategory, minimumSeconds: TimeInterval) throws -> Int {
        let activities = try getActivitiesInRange(from: Date().addingTimeInterval(-86400), to: Date())
        var streak = 0
        var lastActivityDate: Date? = nil
        
        for activity in activities {
            if activity.category == category {
                let activityDate = Calendar.current.startOfDay(for: activity.startTime)
                if let lastActivityDate = lastActivityDate {
                    if activityDate == lastActivityDate {
                        streak += 1
                    } else {
                        streak = 1
                    }
                }
                lastActivityDate = activityDate
            }
        }
        
        return streak
    }
    
    func executeTimeQuery(query: String, arguments: [DatabaseValueConvertible]) throws -> Double {
        return try databaseManager.read { db in
            let result = try Double.fetchOne(db, sql: query, arguments: StatementArguments(arguments)) ?? 0.0
            return result
        }
    }
    
    func executeCountQuery(query: String, arguments: [DatabaseValueConvertible]) throws -> Double {
        return try databaseManager.read { db in
            let result = try Double.fetchOne(db, sql: query, arguments: StatementArguments(arguments)) ?? 0.0
            return result
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCache() {
        cache.name = "com.productivityassistant.activityrecord.cache"
        cache.countLimit = 100 // Limit cache to 100 items
        
        // Setup periodic cache cleanup
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.cleanupExpiredCache()
        }
    }
    
    private func getCachedItem(key: NSString) -> CacheItem? {
        return cacheQueue.sync {
            let item = cache.object(forKey: key)
            
            // Check if item is expired
            if let item = item, Date().timeIntervalSince(item.timestamp) > cacheTimeout {
                cache.removeObject(forKey: key)
                return nil
            }
            
            return item
        }
    }
    
    private func invalidateCacheForDate(_ date: Date) {
        // This is a simplistic approach - in a more sophisticated system,
        // we would track which cache keys might be affected by changes to a date
        cleanupExpiredCache()
    }
    
    private func cleanupExpiredCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // We can't enumerate NSCache directly, so we'll periodically clear it
            // A more sophisticated implementation would track cache keys and their expiration
            if self.cache.totalCostLimit > 0 {
                self.cache.removeAllObjects()
                self.logger.debug("Cleared activity cache due to periodic cleanup")
            }
        }
    }
    
    private func clearCache() {
        cacheQueue.async { [weak self] in
            self?.cache.removeAllObjects()
            self?.logger.debug("Cleared activity cache")
        }
    }
}

/// Cache item wrapper with timestamp for expiration management
class CacheItem: NSObject {
    let value: Any
    let timestamp: Date
    
    init(value: Any, timestamp: Date = Date()) {
        self.value = value
        self.timestamp = timestamp
        super.init()
    }
} 