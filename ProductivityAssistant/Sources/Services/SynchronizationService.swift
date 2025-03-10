import Foundation
import Combine
import os.log

/// Protocol for synchronizing data with external services
protocol SynchronizationService {
    /// Starts the synchronization service
    func start()
    
    /// Stops the synchronization service
    func stop()
    
    /// Triggers an immediate synchronization
    func syncNow() -> AnyPublisher<SyncResult, Error>
    
    /// Returns whether the service is currently syncing
    var isSyncing: Bool { get }
    
    /// Returns whether the service is running
    var isRunning: Bool { get }
    
    /// Returns the last sync time
    var lastSyncTime: Date? { get }
    
    /// Returns the last sync result
    var lastSyncResult: SyncResult? { get }
    
    /// Publisher for sync status updates
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> { get }
}

/// Represents the result of a synchronization operation
struct SyncResult {
    let startTime: Date
    let endTime: Date
    let success: Bool
    let syncedServices: [String]
    let errors: [String: Error]
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

/// Represents the current status of synchronization
enum SyncStatus {
    case idle
    case syncing(progress: Double, service: String)
    case error(message: String)
    case success(result: SyncResult)
}

/// Implementation of SynchronizationService
final class DefaultSynchronizationService: SynchronizationService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Synchronization")
    private let userDefaults: UserDefaults
    private let syncInterval: TimeInterval
    private let retryLimit: Int
    private let retryDelay: TimeInterval
    
    private var syncTimer: Timer?
    private var retryCount: [String: Int] = [:]
    private var syncQueue = DispatchQueue(label: "com.productivityassistant.sync", qos: .utility)
    private var isOffline: Bool = false
    private var syncStatusSubject = CurrentValueSubject<SyncStatus, Never>(.idle)
    private var cancellables = Set<AnyCancellable>()
    
    private var _isSyncing: Bool = false
    private var _isRunning: Bool = false
    private var _lastSyncTime: Date?
    private var _lastSyncResult: SyncResult?
    
    private enum UserDefaultsKeys {
        static let lastSyncTime = "last_sync_time"
    }
    
    // MARK: - Public Properties
    
    var isSyncing: Bool {
        return _isSyncing
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
        return syncStatusSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Services to Sync
    
    private let thingsService: ThingsIntegrationService?
    private let notionService: NotionCalendarService?
    
    // MARK: - Initialization
    
    init(
        userDefaults: UserDefaults = .standard,
        syncInterval: TimeInterval = 15 * 60, // 15 minutes
        retryLimit: Int = 3,
        retryDelay: TimeInterval = 60, // 1 minute
        thingsService: ThingsIntegrationService? = nil,
        notionService: NotionCalendarService? = nil
    ) {
        self.userDefaults = userDefaults
        self.syncInterval = syncInterval
        self.retryLimit = retryLimit
        self.retryDelay = retryDelay
        
        // Get services from app delegate if not provided
        if let thingsService = thingsService {
            self.thingsService = thingsService
        } else if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            self.thingsService = appDelegate.getThingsIntegrationService()
        } else {
            self.thingsService = nil
        }
        
        if let notionService = notionService {
            self.notionService = notionService
        } else if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            self.notionService = appDelegate.getNotionCalendarService()
        } else {
            self.notionService = nil
        }
        
        // Load last sync time
        if let lastSyncTimeInterval = userDefaults.object(forKey: UserDefaultsKeys.lastSyncTime) as? TimeInterval {
            _lastSyncTime = Date(timeIntervalSince1970: lastSyncTimeInterval)
        }
        
        // Setup network monitoring
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    func start() {
        guard !_isRunning else { return }
        
        logger.info("Starting synchronization service")
        _isRunning = true
        
        // Schedule periodic sync
        scheduleSync()
        
        // Initial sync if needed
        if shouldPerformInitialSync() {
            syncNow()
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            self?.logger.error("Initial sync failed: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { [weak self] result in
                        self?.logger.info("Initial sync completed: \(result.success ? "success" : "failure")")
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    func stop() {
        guard _isRunning else { return }
        
        logger.info("Stopping synchronization service")
        _isRunning = false
        
        // Cancel timer
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    func syncNow() -> AnyPublisher<SyncResult, Error> {
        // If already syncing, return a publisher that will complete when the current sync is done
        if _isSyncing {
            return syncStatusPublisher
                .filter { status in
                    if case .success(let result) = status {
                        return true
                    }
                    return false
                }
                .compactMap { status -> SyncResult? in
                    if case .success(let result) = status {
                        return result
                    }
                    return nil
                }
                .first()
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Future<SyncResult, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(SyncError.serviceUnavailable))
                return
            }
            
            // Check if offline
            if self.isOffline {
                promise(.failure(SyncError.offline))
                return
            }
            
            self.syncQueue.async {
                self._isSyncing = true
                self.syncStatusSubject.send(.syncing(progress: 0.0, service: "Preparing"))
                
                let startTime = Date()
                var syncedServices: [String] = []
                var errors: [String: Error] = [:]
                
                // Create a group to wait for all syncs to complete
                let group = DispatchGroup()
                
                // Sync Things 3
                if let thingsService = self.thingsService {
                    group.enter()
                    self.syncThings(thingsService)
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    self.logger.error("Things sync failed: \(error.localizedDescription)")
                                    errors["Things"] = error
                                    self.handleSyncError("Things", error: error)
                                } else {
                                    syncedServices.append("Things")
                                }
                                group.leave()
                            },
                            receiveValue: { _ in }
                        )
                        .store(in: &self.cancellables)
                }
                
                // Sync Notion
                if let notionService = self.notionService, notionService.isAuthenticated {
                    group.enter()
                    self.syncNotion(notionService)
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    self.logger.error("Notion sync failed: \(error.localizedDescription)")
                                    errors["Notion"] = error
                                    self.handleSyncError("Notion", error: error)
                                } else {
                                    syncedServices.append("Notion")
                                }
                                group.leave()
                            },
                            receiveValue: { _ in }
                        )
                        .store(in: &self.cancellables)
                }
                
                // Wait for all syncs to complete
                group.notify(queue: self.syncQueue) {
                    let endTime = Date()
                    let success = errors.isEmpty
                    
                    // Create result
                    let result = SyncResult(
                        startTime: startTime,
                        endTime: endTime,
                        success: success,
                        syncedServices: syncedServices,
                        errors: errors
                    )
                    
                    // Update state
                    self._isSyncing = false
                    self._lastSyncTime = endTime
                    self._lastSyncResult = result
                    
                    // Save last sync time
                    self.userDefaults.set(endTime.timeIntervalSince1970, forKey: UserDefaultsKeys.lastSyncTime)
                    
                    // Log result
                    if success {
                        self.logger.info("Sync completed successfully in \(result.duration) seconds")
                        self.syncStatusSubject.send(.success(result: result))
                    } else {
                        self.logger.error("Sync completed with errors: \(errors.count) services failed")
                        self.syncStatusSubject.send(.error(message: "Sync completed with errors"))
                    }
                    
                    // Reset retry counts for successful services
                    for service in syncedServices {
                        self.retryCount[service] = 0
                    }
                    
                    promise(.success(result))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func scheduleSync() {
        // Cancel existing timer
        syncTimer?.invalidate()
        
        // Create new timer
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self, self._isRunning, !self._isSyncing else { return }
            
            self.syncNow()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            self.logger.error("Scheduled sync failed: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.cancellables)
        }
        
        // Make sure timer fires even when the app is idle
        RunLoop.current.add(syncTimer!, forMode: .common)
    }
    
    private func shouldPerformInitialSync() -> Bool {
        // If never synced before, do initial sync
        guard let lastSyncTime = _lastSyncTime else {
            return true
        }
        
        // If last sync was more than 2x the sync interval ago, do initial sync
        return Date().timeIntervalSince(lastSyncTime) > (syncInterval * 2)
    }
    
    private func setupNetworkMonitoring() {
        // In a real app, we would use NWPathMonitor to detect network changes
        // For simplicity, we'll assume we're always online
        isOffline = false
    }
    
    private func handleSyncError(_ service: String, error: Error) {
        // Increment retry count
        let currentRetryCount = retryCount[service] ?? 0
        retryCount[service] = currentRetryCount + 1
        
        // If we haven't reached the retry limit, schedule a retry
        if currentRetryCount < retryLimit {
            let delay = retryDelay * Double(currentRetryCount + 1)
            logger.info("Scheduling retry for \(service) in \(delay) seconds (attempt \(currentRetryCount + 1)/\(retryLimit))")
            
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self._isRunning, !self._isSyncing else { return }
                
                self.logger.info("Retrying sync for \(service)")
                
                // Retry the specific service
                if service == "Things", let thingsService = self.thingsService {
                    self.syncThings(thingsService)
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    self.logger.error("Things retry failed: \(error.localizedDescription)")
                                    self.handleSyncError("Things", error: error)
                                } else {
                                    self.logger.info("Things retry succeeded")
                                    self.retryCount["Things"] = 0
                                }
                            },
                            receiveValue: { _ in }
                        )
                        .store(in: &self.cancellables)
                } else if service == "Notion", let notionService = self.notionService, notionService.isAuthenticated {
                    self.syncNotion(notionService)
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    self.logger.error("Notion retry failed: \(error.localizedDescription)")
                                    self.handleSyncError("Notion", error: error)
                                } else {
                                    self.logger.info("Notion retry succeeded")
                                    self.retryCount["Notion"] = 0
                                }
                            },
                            receiveValue: { _ in }
                        )
                        .store(in: &self.cancellables)
                }
            }
        } else {
            logger.warning("Retry limit reached for \(service), giving up")
            retryCount[service] = 0
        }
    }
    
    // MARK: - Service-Specific Sync Methods
    
    private func syncThings(_ service: ThingsIntegrationService) -> AnyPublisher<Void, Error> {
        self.syncStatusSubject.send(.syncing(progress: 0.3, service: "Things"))
        
        // For Things, we just need to fetch the latest tasks
        // This is a read-only operation, so there's no conflict resolution needed
        return service.fetchTasks()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    private func syncNotion(_ service: NotionCalendarService) -> AnyPublisher<Void, Error> {
        self.syncStatusSubject.send(.syncing(progress: 0.6, service: "Notion"))
        
        // For Notion, we just need to fetch the latest events
        // This is a read-only operation, so there's no conflict resolution needed
        guard let databaseId = service.activeDatabaseId else {
            return Fail(error: SyncError.noDatabaseSelected).eraseToAnyPublisher()
        }
        
        // Fetch events for the next 7 days
        let now = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        
        return service.fetchEvents(from: now, to: nextWeek)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

/// Error types for synchronization
enum SyncError: Error {
    case offline
    case serviceUnavailable
    case noDatabaseSelected
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .offline:
            return "Device is offline"
        case .serviceUnavailable:
            return "Synchronization service is unavailable"
        case .noDatabaseSelected:
            return "No database selected for Notion"
        case .unknown:
            return "An unknown synchronization error occurred"
        }
    }
} 