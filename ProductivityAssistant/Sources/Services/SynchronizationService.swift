import Foundation
import Combine
import os.log

/// Defines the result of a synchronization operation
struct SyncResult {
    let timestamp: Date
    let successful: Bool
    let errorMessage: String?
    let itemsSynced: Int
    
    static func success(itemCount: Int) -> SyncResult {
        return SyncResult(
            timestamp: Date(),
            successful: true,
            errorMessage: nil,
            itemsSynced: itemCount
        )
    }
    
    static func failure(error: Error) -> SyncResult {
        return SyncResult(
            timestamp: Date(),
            successful: false,
            errorMessage: error.localizedDescription,
            itemsSynced: 0
        )
    }
}

/// Represents the current status of synchronization
enum SyncStatus {
    case idle
    case syncing
    case error(message: String)
    case offline
    
    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing..."
        case .error(let message):
            return "Error: \(message)"
        case .offline:
            return "Offline"
        }
    }
}

/// Protocol defining the operations for synchronizing data with external services
protocol SynchronizationService {
    /// Starts the synchronization service with periodic syncs
    func startService()
    
    /// Stops the synchronization service
    func stopService()
    
    /// Triggers an immediate synchronization
    func syncNow() -> AnyPublisher<SyncResult, Never>
    
    /// The current status of the synchronization
    var syncStatus: SyncStatus { get }
    
    /// Whether the service is running
    var isRunning: Bool { get }
    
    /// The time of the last sync
    var lastSyncTime: Date? { get }
    
    /// The result of the last sync
    var lastSyncResult: SyncResult? { get }
    
    /// Publisher for sync status changes
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> { get }
    
    /// Publisher for sync results
    var syncResultPublisher: AnyPublisher<SyncResult, Never> { get }
}

/// Errors specific to synchronization
enum SynchronizationError: Error {
    case offline
    case serviceUnavailable(String)
    case noDatabaseSelected
    case thingsNotInstalled
    case notionNotAuthenticated
    case maxRetriesExceeded
    case cancelled
    
    var localizedDescription: String {
        switch self {
        case .offline:
            return "Device is offline"
        case .serviceUnavailable(let service):
            return "\(service) service is unavailable"
        case .noDatabaseSelected:
            return "No database selected for synchronization"
        case .thingsNotInstalled:
            return "Things 3 is not installed on this device"
        case .notionNotAuthenticated:
            return "Not authenticated with Notion"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .cancelled:
            return "Synchronization was cancelled"
        }
    }
}

/// Implementation of the SynchronizationService
final class DefaultSynchronizationService: SynchronizationService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Synchronization")
    private let userDefaults: UserDefaults
    private var syncTimer: Timer?
    private var retryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Status
    private var _syncStatus: CurrentValueSubject<SyncStatus, Never>
    private var _lastSyncTime: Date?
    private var _lastSyncResult: SyncResult?
    private var _isRunning: Bool = false
    
    // Publishers
    private let syncResultSubject = PassthroughSubject<SyncResult, Never>()
    
    // Configuration
    private let syncInterval: TimeInterval
    private let maxRetryAttempts: Int
    private let retryDelaySeconds: TimeInterval
    private var currentRetryCount: Int = 0
    
    // Services to sync
    private let thingsService: ThingsIntegrationService?
    private let notionService: NotionCalendarService?
    
    // Public properties
    var syncStatus: SyncStatus {
        return _syncStatus.value
    }
    
    var isRunning: Bool {
        return _isRunning
    }
    
    var lastSyncTime: Date? {
        return _lastSyncTime
    }
    
    var lastSyncResult: SyncResult? {
        return _lastSyncResult
    }
    
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> {
        return _syncStatus.eraseToAnyPublisher()
    }
    
    var syncResultPublisher: AnyPublisher<SyncResult, Never> {
        return syncResultSubject.eraseToAnyPublisher()
    }
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let lastSyncTime = "lastSyncTime"
        static let syncInterval = "syncIntervalMinutes"
        static let autoSyncEnabled = "autoSyncEnabled"
    }
    
    // MARK: - Initialization
    
    init(
        thingsService: ThingsIntegrationService? = nil,
        notionService: NotionCalendarService? = nil,
        userDefaults: UserDefaults = .standard,
        syncInterval: TimeInterval = 30 * 60, // Default: 30 minutes
        maxRetryAttempts: Int = 3,
        retryDelaySeconds: TimeInterval = 60 // Default: 1 minute
    ) {
        self.thingsService = thingsService
        self.notionService = notionService
        self.userDefaults = userDefaults
        self.syncInterval = userDefaults.double(forKey: UserDefaultsKeys.syncInterval) > 0 
            ? userDefaults.double(forKey: UserDefaultsKeys.syncInterval) * 60 
            : syncInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelaySeconds = retryDelaySeconds
        
        // Initialize status
        self._syncStatus = CurrentValueSubject<SyncStatus, Never>(.idle)
        
        // Load last sync time from UserDefaults if available
        if let lastSyncTimeDate = userDefaults.object(forKey: UserDefaultsKeys.lastSyncTime) as? Date {
            self._lastSyncTime = lastSyncTimeDate
        }
        
        // Start service if auto-sync is enabled
        if userDefaults.bool(forKey: UserDefaultsKeys.autoSyncEnabled) {
            startService()
        }
        
        // Monitor network connectivity changes
        monitorNetworkConnectivity()
    }
    
    // MARK: - Public Methods
    
    func startService() {
        guard !_isRunning else { return }
        
        logger.info("Starting synchronization service")
        _isRunning = true
        
        // Schedule periodic sync
        schedulePeriodicSync()
        
        // Set auto-sync to enabled in user defaults
        userDefaults.set(true, forKey: UserDefaultsKeys.autoSyncEnabled)
    }
    
    func stopService() {
        guard _isRunning else { return }
        
        logger.info("Stopping synchronization service")
        _isRunning = false
        
        // Invalidate timers
        syncTimer?.invalidate()
        syncTimer = nil
        
        retryTimer?.invalidate()
        retryTimer = nil
        
        // Update status
        _syncStatus.send(.idle)
        
        // Set auto-sync to disabled in user defaults
        userDefaults.set(false, forKey: UserDefaultsKeys.autoSyncEnabled)
    }
    
    func syncNow() -> AnyPublisher<SyncResult, Never> {
        // Already syncing, return a publisher that will complete when the current sync finishes
        if case .syncing = _syncStatus.value {
            logger.info("Sync already in progress, ignoring syncNow request")
            return syncResultPublisher.first().eraseToAnyPublisher()
        }
        
        logger.info("Initiating immediate sync")
        _syncStatus.send(.syncing)
        
        // Check network connectivity
        if !isNetworkReachable() {
            logger.warning("Device is offline, cannot sync")
            let result = SyncResult.failure(error: SynchronizationError.offline)
            handleSyncCompletion(result: result)
            return Just(result).eraseToAnyPublisher()
        }
        
        // Perform sync for all services
        return performFullSync()
            .handleEvents(
                receiveOutput: { [weak self] result in
                    self?.handleSyncCompletion(result: result)
                },
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Sync failed: \(error.localizedDescription)")
                        let result = SyncResult.failure(error: error)
                        self?.handleSyncCompletion(result: result)
                    }
                }
            )
            .catch { error -> Just<SyncResult> in
                return Just(SyncResult.failure(error: error))
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func schedulePeriodicSync() {
        // Cancel existing timer if any
        syncTimer?.invalidate()
        
        // Create new timer
        syncTimer = Timer.scheduledTimer(
            withTimeInterval: syncInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            
            // Skip sync if we're already syncing
            if case .syncing = self._syncStatus.value {
                self.logger.info("Skipping scheduled sync - sync already in progress")
                return
            }
            
            self.logger.info("Starting scheduled sync")
            self.syncNow()
                .sink { _ in }
                .store(in: &self.cancellables)
        }
        
        // Make sure timer fires even when the app is in background
        RunLoop.current.add(syncTimer!, forMode: .common)
        
        // Also perform an immediate sync on startup if it's been a while
        if let lastSyncTime = _lastSyncTime, 
           Date().timeIntervalSince(lastSyncTime) > syncInterval {
            logger.info("Performing initial sync on service start")
            syncNow()
                .sink { _ in }
                .store(in: &cancellables)
        }
    }
    
    private func handleSyncCompletion(result: SyncResult) {
        // Update status based on result
        if result.successful {
            _syncStatus.send(.idle)
            _lastSyncTime = result.timestamp
            currentRetryCount = 0  // Reset retry count on success
            
            // Save last sync time to UserDefaults
            userDefaults.set(result.timestamp, forKey: UserDefaultsKeys.lastSyncTime)
        } else {
            if !isNetworkReachable() {
                _syncStatus.send(.offline)
            } else {
                _syncStatus.send(.error(message: result.errorMessage ?? "Unknown error"))
                
                // Schedule retry if not reached max attempts
                if currentRetryCount < maxRetryAttempts {
                    scheduleRetry()
                }
            }
        }
        
        // Update last result
        _lastSyncResult = result
        
        // Emit result to subscribers
        syncResultSubject.send(result)
        
        logger.info("Sync completed: \(result.successful ? "Success" : "Failed"), Items: \(result.itemsSynced)")
    }
    
    private func scheduleRetry() {
        currentRetryCount += 1
        
        // Cancel existing retry timer if any
        retryTimer?.invalidate()
        
        // Calculate exponential backoff delay
        let delay = retryDelaySeconds * pow(2.0, Double(currentRetryCount - 1))
        logger.info("Scheduling retry #\(currentRetryCount) in \(Int(delay)) seconds")
        
        // Create new timer
        retryTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            
            self.logger.info("Executing retry #\(self.currentRetryCount)")
            self.syncNow()
                .sink { _ in }
                .store(in: &self.cancellables)
        }
        
        // Make sure timer fires even when the app is in background
        RunLoop.current.add(retryTimer!, forMode: .common)
    }
    
    private func performFullSync() -> AnyPublisher<SyncResult, Error> {
        var publishers = [AnyPublisher<Int, Error>]()
        
        // Add Things sync if available
        if let thingsService = thingsService {
            publishers.append(syncThings(service: thingsService))
        }
        
        // Add Notion sync if available
        if let notionService = notionService {
            publishers.append(syncNotion(service: notionService))
        }
        
        // If no services to sync, return empty success
        if publishers.isEmpty {
            return Just(SyncResult.success(itemCount: 0))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Combine all sync operations
        return Publishers.MergeMany(publishers)
            .collect()
            .map { itemCounts in
                let totalItems = itemCounts.reduce(0, +)
                return SyncResult.success(itemCount: totalItems)
            }
            .eraseToAnyPublisher()
    }
    
    private func syncThings(service: ThingsIntegrationService) -> AnyPublisher<Int, Error> {
        return service.fetchAllTasks()
            .map { tasks in
                self.logger.info("Synced \(tasks.count) tasks from Things")
                return tasks.count
            }
            .mapError { error in
                self.logger.error("Things sync error: \(error.localizedDescription)")
                
                if let thingsError = error as? ThingsIntegrationError {
                    switch thingsError {
                    case .notInstalled:
                        return SynchronizationError.thingsNotInstalled
                    default:
                        return SynchronizationError.serviceUnavailable("Things 3")
                    }
                }
                return error
            }
            .eraseToAnyPublisher()
    }
    
    private func syncNotion(service: NotionCalendarService) -> AnyPublisher<Int, Error> {
        return service.fetchSelectedDatabases()
            .flatMap { databases -> AnyPublisher<[NotionEvent], Error> in
                guard !databases.isEmpty else {
                    return Fail(error: SynchronizationError.noDatabaseSelected)
                        .eraseToAnyPublisher()
                }
                
                // Fetch events for each database and combine results
                let eventPublishers = databases.map { database in
                    return service.fetchEvents(for: database.id, startDate: Date(), days: 7)
                }
                
                return Publishers.MergeMany(eventPublishers)
                    .collect()
                    .map { eventArrays in
                        return eventArrays.flatMap { $0 }
                    }
                    .eraseToAnyPublisher()
            }
            .map { events in
                self.logger.info("Synced \(events.count) events from Notion")
                return events.count
            }
            .mapError { error in
                self.logger.error("Notion sync error: \(error.localizedDescription)")
                
                if let notionError = error as? NotionIntegrationError {
                    switch notionError {
                    case .notAuthenticated, .invalidToken:
                        return SynchronizationError.notionNotAuthenticated
                    case .databaseNotFound:
                        return SynchronizationError.noDatabaseSelected
                    default:
                        return SynchronizationError.serviceUnavailable("Notion")
                    }
                }
                return error
            }
            .eraseToAnyPublisher()
    }
    
    private func isNetworkReachable() -> Bool {
        // Simple implementation - in a real app, this would use NWPathMonitor
        // or Reachability to check for actual network connectivity
        
        // For now, we'll assume the network is available
        return true
    }
    
    private func monitorNetworkConnectivity() {
        // In a real app, we would use NWPathMonitor to monitor network changes
        // and update our sync status accordingly
        
        // For demonstration purposes, we'll simulate being online
        // A real implementation would set up a PathMonitor and listen for status changes
    }
} 
 