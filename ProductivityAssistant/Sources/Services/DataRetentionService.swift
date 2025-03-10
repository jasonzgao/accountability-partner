import Foundation
import Combine
import os.log

protocol DataRetentionServiceProtocol {
    /// Applies the data retention policy immediately
    func applyRetentionPolicy() throws -> Int
    
    /// Updates the retention period
    func updateRetentionPeriod(days: Int)
    
    /// Clears all stored data
    func clearAllData() throws -> Int
    
    /// Current retention period in days
    var retentionPeriodDays: Int { get }
}

/// Service responsible for managing data retention policies
final class DataRetentionService: DataRetentionServiceProtocol {
    // MARK: - Properties
    
    private let activityRepository: ActivityRecordRepositoryProtocol
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.productivityassistant", category: "DataRetention")
    private var retentionPolicyTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let retentionPeriodDays = "retentionPeriodDays"
        static let lastCleanupDate = "lastRetentionCleanupDate"
    }
    
    // Default retention period (30 days) if not specified
    private let defaultRetentionPeriodDays = 30
    
    var retentionPeriodDays: Int {
        get {
            return userDefaults.integer(forKey: UserDefaultsKeys.retentionPeriodDays)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.retentionPeriodDays)
        }
    }
    
    // MARK: - Initialization
    
    init(activityRepository: ActivityRecordRepositoryProtocol, userDefaults: UserDefaults = .standard) {
        self.activityRepository = activityRepository
        self.userDefaults = userDefaults
        
        // Set default retention period if not set
        if userDefaults.integer(forKey: UserDefaultsKeys.retentionPeriodDays) == 0 {
            userDefaults.set(defaultRetentionPeriodDays, forKey: UserDefaultsKeys.retentionPeriodDays)
        }
        
        setupPeriodicCleanup()
    }
    
    // MARK: - Public Methods
    
    func applyRetentionPolicy() throws -> Int {
        logger.info("Applying data retention policy with \(self.retentionPeriodDays) days retention period")
        
        let deletedCount = try activityRepository.applyRetentionPolicy(retentionDays: retentionPeriodDays)
        
        // Update last cleanup date
        userDefaults.set(Date(), forKey: UserDefaultsKeys.lastCleanupDate)
        
        return deletedCount
    }
    
    func updateRetentionPeriod(days: Int) {
        guard days > 0 else {
            logger.error("Attempted to set invalid retention period: \(days) days")
            return
        }
        
        retentionPeriodDays = days
        logger.info("Updated retention period to \(days) days")
        
        // Reset the timer to apply new retention period
        setupPeriodicCleanup()
    }
    
    func clearAllData() throws -> Int {
        logger.info("Clearing all stored data")
        return try activityRepository.clearAllData()
    }
    
    // MARK: - Private Methods
    
    private func setupPeriodicCleanup() {
        // Invalidate existing timer if any
        retentionPolicyTimer?.invalidate()
        
        // Check if cleanup is needed on startup
        checkAndCleanupIfNeeded()
        
        // Schedule daily cleanup check
        retentionPolicyTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkAndCleanupIfNeeded()
        }
        
        // Make sure timer fires even when the app is idle
        RunLoop.current.add(retentionPolicyTimer!, forMode: .common)
    }
    
    private func checkAndCleanupIfNeeded() {
        // Get the last cleanup date
        let lastCleanupDate = userDefaults.object(forKey: UserDefaultsKeys.lastCleanupDate) as? Date ?? Date.distantPast
        
        // If last cleanup was more than 1 day ago, apply retention policy
        if Date().timeIntervalSince(lastCleanupDate) > 24 * 60 * 60 {
            do {
                let deletedCount = try applyRetentionPolicy()
                logger.info("Automatic cleanup completed. Deleted \(deletedCount) old records.")
            } catch {
                logger.error("Failed to apply automatic retention policy: \(error.localizedDescription)")
            }
        }
    }
} 