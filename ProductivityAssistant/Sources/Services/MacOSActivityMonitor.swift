import Foundation
import Combine
import AppKit
import ApplicationServices
import os.log

/// Implementation of ActivityMonitorService for macOS
final class MacOSActivityMonitor: ActivityMonitorService {
    // MARK: - Properties
    
    private let activityRepository: ActivityRecordRepositoryProtocol
    private let categoryRepository: CategoryRepositoryProtocol
    private let browserIntegration: BrowserIntegrationService
    private let appleScriptManager = AppleScriptManager.shared
    private let logger = Logger(subsystem: "com.productivityassistant", category: "ActivityMonitor")
    
    private var monitoringTimer: Timer?
    private var idleTimer: Timer?
    private var currentActivity: ActivityRecord?
    private var lastIdleCheck = Date()
    private var isCurrentlyIdle = false
    
    private let activitySubject = PassthroughSubject<ActivityRecord, Error>()
    private let idleStateSubject = PassthroughSubject<Bool, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private let monitoringInterval: TimeInterval = 2.0 // Check active app every 2 seconds
    private let idleCheckInterval: TimeInterval = 5.0 // Check idle status every 5 seconds
    
    var isMonitoring: Bool {
        return monitoringTimer != nil
    }
    
    var isUserIdle: Bool {
        return isCurrentlyIdle
    }
    
    var idleThreshold: TimeInterval = 300.0 // 5 minutes default
    
    var idleStatePublisher: AnyPublisher<Bool, Never> {
        return idleStateSubject.eraseToAnyPublisher()
    }
    
    var hasAccessibilityPermissions: Bool {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Initialization
    
    init(activityRepository: ActivityRecordRepositoryProtocol, 
         categoryRepository: CategoryRepositoryProtocol,
         browserIntegration: BrowserIntegrationService? = nil) {
        self.activityRepository = activityRepository
        self.categoryRepository = categoryRepository
        self.browserIntegration = browserIntegration ?? MacOSBrowserIntegration(categoryRepository: categoryRepository)
        
        // Listen for browser tab changes
        self.browserIntegration.tabChangePublisher
            .sink { [weak self] browserInfo in
                self?.handleBrowserTabChange(browser: browserInfo.browser, url: browserInfo.url)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() -> AnyPublisher<ActivityRecord, Error> {
        // Check if we already have monitoring running
        guard monitoringTimer == nil else {
            return activitySubject.eraseToAnyPublisher()
        }
        
        // Check accessibility permissions
        guard hasAccessibilityPermissions else {
            activitySubject.send(completion: .failure(ActivityMonitorError.accessibilityPermissionDenied))
            return activitySubject.eraseToAnyPublisher()
        }
        
        logger.info("Starting activity monitoring")
        
        // Start the monitoring timer using a RunLoop to keep it active even when the app is idle
        monitoringTimer = Timer(timeInterval: monitoringInterval, target: self, selector: #selector(checkCurrentActivityTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(monitoringTimer!, forMode: .common)
        
        // Start the idle timer
        idleTimer = Timer(timeInterval: idleCheckInterval, target: self, selector: #selector(checkIdleStatusTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(idleTimer!, forMode: .common)
        
        // Initialize by checking the current activity
        checkCurrentActivity()
        
        return activitySubject.eraseToAnyPublisher()
    }
    
    func stopMonitoring() {
        logger.info("Stopping activity monitoring")
        
        // Invalidate timers
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        idleTimer?.invalidate()
        idleTimer = nil
        
        // Close out the current activity if needed
        if let currentActivity = currentActivity, currentActivity.endTime == nil {
            var updatedActivity = currentActivity
            updatedActivity.endTime = Date()
            
            do {
                try activityRepository.update(updatedActivity)
                self.currentActivity = nil
                logger.debug("Closed out current activity: \(currentActivity.applicationName)")
            } catch {
                logger.error("Error ending current activity: \(error.localizedDescription)")
            }
        }
    }
    
    func getCurrentActivity() -> ActivityRecord? {
        return currentActivity
    }
    
    func categorizeActivity(_ record: ActivityRecord, as category: ActivityCategory) {
        // Update the category on the record
        var updatedRecord = record
        updatedRecord.category = category
        
        do {
            try activityRepository.update(updatedRecord)
            logger.info("Categorized activity \(record.applicationName) as \(category.rawValue)")
            
            // If this is the current activity, update that too
            if let currentActivity = currentActivity, currentActivity.id == record.id {
                self.currentActivity = updatedRecord
            }
            
            // Create or update the categorization rule
            let applicationName = record.applicationName
            let urlPattern = record.url?.host
            
            if let existingRules = try? categoryRepository.getCategoryRulesByApplication(applicationName: applicationName) {
                let categoryId = ActivityCategoryType.from(category).rawValue
                
                // Check if we already have a matching rule
                let matchingRule = existingRules.first { rule in
                    if let urlPattern = urlPattern, let ruleUrlPattern = rule.urlPattern {
                        return rule.categoryId == categoryId && ruleUrlPattern.contains(urlPattern)
                    } else {
                        return rule.categoryId == categoryId && rule.urlPattern == nil
                    }
                }
                
                if matchingRule == nil {
                    // Create a new rule
                    let rule = CategoryRule(
                        applicationName: applicationName,
                        urlPattern: urlPattern,
                        windowTitlePattern: nil,
                        categoryId: categoryId
                    )
                    
                    try? categoryRepository.saveCategoryRule(rule)
                    logger.info("Created new category rule for \(applicationName) with category \(categoryId)")
                }
            }
        } catch {
            logger.error("Error updating activity category: \(error.localizedDescription)")
        }
    }
    
    func requestAccessibilityPermissions() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Private Methods
    
    @objc private func checkCurrentActivityTimerFired() {
        checkCurrentActivity()
    }
    
    @objc private func checkIdleStatusTimerFired() {
        checkIdleStatus()
    }
    
    private func checkCurrentActivity() {
        // Don't update if the user is idle
        guard !isUserIdle else { return }
        
        guard let activeApp = getActiveApplication(),
              let appName = activeApp.localizedName else {
            return
        }
        
        // Get window information
        var windowTitle: String?
        var url: URL?
        
        if browserIntegration.isSupportedBrowser(appName) {
            // For browsers, use the browser integration service
            url = browserIntegration.getCurrentURL(for: appName)
            windowTitle = appleScriptManager.getWindowTitle(for: appName)
        } else {
            // For other apps, just get the window title
            windowTitle = appleScriptManager.getWindowTitle(for: appName)
        }
        
        // Determine application type
        let applicationType = ApplicationType.fromApplicationName(appName)
        
        // Determine category based on the application and URL
        var category: ActivityCategory
        
        if let url = url, browserIntegration.isSupportedBrowser(appName) {
            // Use the browser integration service for URL categorization
            category = browserIntegration.categorizeURL(url)
        } else {
            // Use the standard activity categorization
            category = ActivityCategory.categorize(applicationName: appName, url: url, windowTitle: windowTitle)
        }
        
        // Check custom rules from repository for more accurate categorization
        var finalCategory = category
        if let appRules = try? categoryRepository.getCategoryRulesByApplication(applicationName: appName) {
            for rule in appRules {
                // Check for URL pattern match
                if let urlPattern = rule.urlPattern, let activityUrl = url, let host = activityUrl.host {
                    if host.contains(urlPattern) {
                        if let categoryRecord = try? categoryRepository.getCategoryById(id: rule.categoryId) {
                            finalCategory = categoryRecord.type.toActivityCategory
                            break
                        }
                    }
                } 
                // Check for window title match
                else if let titlePattern = rule.windowTitlePattern, let title = windowTitle {
                    if title.contains(titlePattern) {
                        if let categoryRecord = try? categoryRepository.getCategoryById(id: rule.categoryId) {
                            finalCategory = categoryRecord.type.toActivityCategory
                            break
                        }
                    }
                }
                // Application-level match with no specific pattern
                else if rule.urlPattern == nil && rule.windowTitlePattern == nil {
                    if let categoryRecord = try? categoryRepository.getCategoryById(id: rule.categoryId) {
                        finalCategory = categoryRecord.type.toActivityCategory
                        break
                    }
                }
            }
        }
        
        let now = Date()
        
        // Check if we need to update the current activity or create a new one
        if let currentActivity = currentActivity {
            // Check if the application or category has changed
            if currentActivity.applicationName != appName || 
               currentActivity.category != finalCategory ||
               currentActivity.url?.absoluteString != url?.absoluteString {
                
                // End the current activity
                var updatedActivity = currentActivity
                updatedActivity.endTime = now
                
                do {
                    try activityRepository.update(updatedActivity)
                    logger.debug("Ended activity: \(currentActivity.applicationName)")
                    
                    // Create a new activity
                    let newActivity = ActivityRecord(
                        startTime: now,
                        applicationType: applicationType,
                        applicationName: appName,
                        windowTitle: windowTitle,
                        url: url,
                        category: finalCategory
                    )
                    
                    try activityRepository.save(newActivity)
                    self.currentActivity = newActivity
                    activitySubject.send(newActivity)
                    logger.debug("Started new activity: \(appName)")
                } catch {
                    logger.error("Error updating activity: \(error.localizedDescription)")
                }
            }
            // Same app but possibly different window/URL - update the current record
            else if currentActivity.windowTitle != windowTitle || 
                    currentActivity.url?.absoluteString != url?.absoluteString {
                
                var updatedActivity = currentActivity
                updatedActivity.windowTitle = windowTitle
                updatedActivity.url = url
                
                do {
                    try activityRepository.update(updatedActivity)
                    self.currentActivity = updatedActivity
                    logger.debug("Updated activity details for \(appName)")
                } catch {
                    logger.error("Error updating activity details: \(error.localizedDescription)")
                }
            }
        } else {
            // No current activity, create a new one
            let newActivity = ActivityRecord(
                startTime: now,
                applicationType: applicationType,
                applicationName: appName,
                windowTitle: windowTitle,
                url: url,
                category: finalCategory
            )
            
            do {
                try activityRepository.save(newActivity)
                self.currentActivity = newActivity
                activitySubject.send(newActivity)
                logger.debug("Created first activity: \(appName)")
            } catch {
                logger.error("Error creating new activity: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkIdleStatus() {
        let idleTime = getSystemIdleTime()
        let wasIdle = isCurrentlyIdle
        
        // Update idle state
        isCurrentlyIdle = idleTime >= idleThreshold
        
        // Notify if idle state changed
        if wasIdle != isCurrentlyIdle {
            idleStateSubject.send(isCurrentlyIdle)
            logger.info("Idle state changed: \(isCurrentlyIdle ? "idle" : "active")")
            
            if isCurrentlyIdle {
                // User became idle, end the current activity
                if let currentActivity = currentActivity, currentActivity.endTime == nil {
                    var updatedActivity = currentActivity
                    updatedActivity.endTime = Date()
                    
                    do {
                        try activityRepository.update(updatedActivity)
                        self.currentActivity = nil
                        logger.debug("Ended activity due to idle: \(currentActivity.applicationName)")
                    } catch {
                        logger.error("Error ending current activity due to idle: \(error.localizedDescription)")
                    }
                }
            } else {
                // User returned from idle, immediately check current activity
                checkCurrentActivity()
            }
        }
    }
    
    private func getSystemIdleTime() -> TimeInterval {
        // Use CGEventSourceSecondsSinceLastEventType to get idle time
        let kCGAnyInputEventType = UInt32(CGEventType.otherMouseDown.rawValue)
        let idleTime = CGEventSourceSecondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)
        return idleTime
    }
    
    private func getActiveApplication() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    private func handleBrowserTabChange(browser: String, url: URL) {
        // Update the current activity if the browser is active
        if let currentActivity = currentActivity,
           browserIntegration.isSupportedBrowser(currentActivity.applicationName),
           currentActivity.applicationName.contains(browser) {
            
            logger.info("Browser tab changed in \(browser): \(url.absoluteString)")
            
            // Categorize the URL
            let category = browserIntegration.categorizeURL(url)
            
            // End the current activity
            var updatedActivity = currentActivity
            updatedActivity.endTime = Date()
            
            do {
                try activityRepository.update(updatedActivity)
                
                // Create a new activity for the new tab
                let newActivity = ActivityRecord(
                    startTime: Date(),
                    applicationType: .browserTab,
                    applicationName: currentActivity.applicationName,
                    windowTitle: currentActivity.windowTitle,
                    url: url,
                    category: category
                )
                
                try activityRepository.save(newActivity)
                self.currentActivity = newActivity
                activitySubject.send(newActivity)
                logger.debug("Updated activity for browser tab change: \(url.absoluteString)")
            } catch {
                logger.error("Error handling browser tab change: \(error.localizedDescription)")
            }
        }
    }
    
    private func extractURLFromBrowser(appName: String) -> URL? {
        // Use the browser integration service
        return browserIntegration.getCurrentURL(for: appName)
    }
}

/// Errors that can occur during activity monitoring
enum ActivityMonitorError: Error {
    case accessibilityPermissionDenied
    case monitoringFailure(String)
}

/// Simple struct to hold window information
struct WindowInfo {
    let title: String
    let app: NSRunningApplication
} 