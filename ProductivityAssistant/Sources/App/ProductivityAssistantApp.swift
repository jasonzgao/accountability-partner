import SwiftUI
import Combine
import os.log

@main
struct ProductivityAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "AppDelegate")
    
    private var activityMonitorService: ActivityMonitorService!
    private var activityRepository: ActivityRecordRepositoryProtocol!
    private var categoryRepository: CategoryRepositoryProtocol!
    private var browserIntegrationService: BrowserIntegrationService!
    private var categorizationService: ActivityCategorizationService!
    private var statisticsService: ActivityStatisticsService!
    private var dataRetentionService: DataRetentionServiceProtocol!
    private var thingsIntegrationService: ThingsIntegrationService!
    private var notionCalendarService: NotionCalendarService!
    private var authenticationManager: AuthenticationManagerProtocol!
    private var synchronizationService: SynchronizationService!
    private var goalRepository: GoalRepositoryProtocol!
    private var goalTrackingService: GoalTrackingService!
    private var habitDetectionService: HabitDetectionService!
    private var notificationService: NotificationService!
    
    // MARK: - Service Access
    
    /// Returns the activity monitor service for use by view models
    func getActivityMonitor() -> ActivityMonitorService {
        return activityMonitorService
    }
    
    /// Returns the activity repository for use by view models
    func getActivityRepository() -> ActivityRecordRepositoryProtocol {
        return activityRepository
    }
    
    /// Returns the category repository for use by view models
    func getCategoryRepository() -> CategoryRepositoryProtocol {
        return categoryRepository
    }
    
    /// Returns the browser integration service for use by view models
    func getBrowserIntegrationService() -> BrowserIntegrationService {
        return browserIntegrationService
    }
    
    /// Returns the activity categorization service for use by view models
    func getCategorizationService() -> ActivityCategorizationService {
        return categorizationService
    }
    
    /// Returns the activity statistics service for use by view models
    func getStatisticsService() -> ActivityStatisticsService {
        return statisticsService
    }
    
    /// Returns the data retention service for use by view models
    func getDataRetentionService() -> DataRetentionServiceProtocol {
        return dataRetentionService
    }
    
    /// Returns the Things integration service for use by view models
    func getThingsIntegrationService() -> ThingsIntegrationService {
        return thingsIntegrationService
    }
    
    /// Returns the Notion calendar service for use by view models
    func getNotionCalendarService() -> NotionCalendarService {
        return notionCalendarService
    }
    
    /// Returns the authentication manager for use by view models
    func getAuthenticationManager() -> AuthenticationManagerProtocol {
        return authenticationManager
    }
    
    /// Returns the synchronization service for use by view models
    func getSynchronizationService() -> SynchronizationService {
        return synchronizationService
    }
    
    /// Returns the goal repository for use by view models
    func getGoalRepository() -> GoalRepositoryProtocol {
        return goalRepository
    }
    
    /// Returns the goal tracking service for use by view models
    func getGoalTrackingService() -> GoalTrackingService {
        return goalTrackingService
    }
    
    /// Returns the habit detection service for use by view models
    func getHabitDetectionService() -> HabitDetectionService {
        return habitDetectionService
    }
    
    /// Returns the notification service for use by view models
    func getNotificationService() -> NotificationService {
        return notificationService
    }
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")
        
        // Initialize database
        do {
            try setupDatabase()
            logger.info("Database initialized successfully")
        } catch {
            logger.error("Failed to initialize database: \(error.localizedDescription)")
        }
        
        // Setup authentication manager
        setupAuthenticationManager()
        
        // Setup repositories
        setupRepositories()
        
        // Setup browser integration
        setupBrowserIntegration()
        
        // Setup categorization service
        setupCategorizationService()
        
        // Setup statistics service
        setupStatisticsService()
        
        // Setup data retention service
        setupDataRetentionService()
        
        // Setup Things integration
        setupThingsIntegration()
        
        // Setup Notion calendar integration
        setupNotionCalendarIntegration()
        
        // Setup synchronization service
        setupSynchronizationService()
        
        // Setup goal tracking
        setupGoalTracking()
        
        // Setup habit detection
        setupHabitDetection()
        
        // Setup notification service
        setupNotificationService()
        
        // Setup activity monitor
        setupActivityMonitor()
        
        // Setup menu bar
        setupMenuBar()
        
        // Request permissions
        requestPermissions()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop monitoring when app terminates
        activityMonitorService.stopMonitoring()
        logger.info("Activity monitoring stopped due to app termination")
    }
    
    // MARK: - Setup Methods
    
    private func setupAuthenticationManager() {
        authenticationManager = KeychainAuthenticationManager()
        logger.info("Authentication manager initialized")
    }
    
    private func setupDatabase() throws {
        // Initialize the database manager
        try DatabaseManager.shared.setup()
        
        // Insert default categories if not present
        let categoryRepository = CategoryRepository()
        let defaultCategories = createDefaultCategories()
        
        // Check if categories exist
        let existingCategories = try categoryRepository.getAllCategories()
        if existingCategories.isEmpty {
            // Insert default categories
            for category in defaultCategories {
                try categoryRepository.saveCategory(category)
            }
            logger.info("Inserted default categories")
        }
    }
    
    private func setupRepositories() {
        activityRepository = ActivityRecordRepository()
        categoryRepository = CategoryRepository()
    }
    
    private func setupBrowserIntegration() {
        browserIntegrationService = MacOSBrowserIntegration(categoryRepository: categoryRepository)
        logger.info("Browser integration service initialized")
    }
    
    private func setupCategorizationService() {
        categorizationService = DefaultActivityCategorizationService(
            categoryRepository: categoryRepository,
            browserIntegration: browserIntegrationService
        )
        logger.info("Activity categorization service initialized")
    }
    
    private func setupStatisticsService() {
        statisticsService = DefaultActivityStatisticsService(
            activityRepository: activityRepository
        )
        logger.info("Activity statistics service initialized")
    }
    
    private func setupDataRetentionService() {
        dataRetentionService = DataRetentionService(
            activityRepository: activityRepository
        )
        logger.info("Data retention service initialized")
    }
    
    private func setupThingsIntegration() {
        thingsIntegrationService = AppleScriptThingsIntegration()
        
        if thingsIntegrationService.isThingsInstalled {
            logger.info("Things 3 integration service initialized successfully")
        } else {
            logger.warning("Things 3 integration service initialized, but Things 3 is not installed")
        }
    }
    
    private func setupNotionCalendarIntegration() {
        notionCalendarService = NotionAPICalendarService()
        logger.info("Notion calendar integration service initialized")
    }
    
    private func setupSynchronizationService() {
        synchronizationService = DefaultSynchronizationService(
            thingsService: thingsIntegrationService,
            notionService: notionCalendarService
        )
        logger.info("Synchronization service initialized")
    }
    
    private func setupGoalTracking() {
        goalRepository = GoalRepository()
        
        goalTrackingService = DefaultGoalTrackingService(
            goalRepository: goalRepository,
            activityRepository: activityRepository
        )
        
        logger.info("Goal repository and tracking service initialized")
    }
    
    private func setupHabitDetection() {
        habitDetectionService = DefaultHabitDetectionService(
            activityRepository: activityRepository
        )
        
        logger.info("Habit detection service initialized")
    }
    
    private func setupNotificationService() {
        notificationService = DefaultNotificationService()
        
        logger.info("Notification service initialized")
    }
    
    private func setupActivityMonitor() {
        activityMonitorService = MacOSActivityMonitor(
            activityRepository: activityRepository,
            categoryRepository: categoryRepository,
            browserIntegration: browserIntegrationService
        )
        
        // Subscribe to activity updates
        activityMonitorService.startMonitoring()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Activity monitoring failed: \(error.localizedDescription)")
                        
                        if let monitorError = error as? ActivityMonitorError,
                           monitorError == ActivityMonitorError.accessibilityPermissionDenied {
                            self?.requestPermissions()
                        }
                    }
                },
                receiveValue: { [weak self] activity in
                    self?.handleActivityUpdate(activity)
                }
            )
            .store(in: &cancellables)
        
        // Subscribe to idle state changes
        activityMonitorService.idleStatePublisher
            .sink { [weak self] isIdle in
                self?.handleIdleStateChange(isIdle)
            }
            .store(in: &cancellables)
            
        logger.info("Activity monitoring service initialized")
    }
    
    private func setupMenuBar() {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Productivity Assistant")
            button.action = #selector(togglePopover)
        }
        
        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
    }
    
    private func requestPermissions() {
        PermissionsHandler.shared.requestAllPermissions { [weak self] granted in
            guard let self = self else { return }
            
            if granted {
                self.logger.info("All permissions granted, starting activity monitoring")
                
                // Start activity monitoring if not already running
                if !self.activityMonitorService.isMonitoring {
                    _ = self.activityMonitorService.startMonitoring()
                }
            } else {
                self.logger.warning("Not all permissions were granted")
                
                // Show alert about missing permissions
                let alert = NSAlert()
                alert.messageText = "Permissions Required"
                alert.informativeText = "Productivity Assistant needs accessibility permissions to function correctly. You can grant these permissions in System Preferences > Security & Privacy > Privacy > Accessibility."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    private func createDefaultCategories() -> [ActivityCategoryRecord] {
        return [
            ActivityCategoryRecord(id: "productive", name: "Productive", type: .productive, color: "#4CAF50"),
            ActivityCategoryRecord(id: "neutral", name: "Neutral", type: .neutral, color: "#FFC107"),
            ActivityCategoryRecord(id: "distracting", name: "Distracting", type: .distracting, color: "#F44336")
        ]
    }
    
    // MARK: - Event Handlers
    
    private func handleActivityUpdate(_ activity: ActivityRecord) {
        logger.debug("Activity updated: \(activity.applicationName) (\(activity.category.rawValue))")
        
        // Update menu bar icon based on activity category
        DispatchQueue.main.async { [weak self] in
            self?.updateMenuBarIcon(for: activity.category)
        }
    }
    
    private func handleIdleStateChange(_ isIdle: Bool) {
        logger.debug("Idle state changed: \(isIdle ? "idle" : "active")")
        
        if isIdle {
            // Update menu bar icon to show idle state
            DispatchQueue.main.async { [weak self] in
                self?.updateMenuBarIcon(for: nil)
            }
        }
    }
    
    private func updateMenuBarIcon(for category: ActivityCategory?) {
        guard let button = statusItem.button else { return }
        
        if let category = category {
            // Set icon based on category
            switch category {
            case .productive:
                button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Productive")
                button.contentTintColor = NSColor.systemGreen
            case .neutral:
                button.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Neutral")
                button.contentTintColor = NSColor.systemYellow
            case .distracting:
                button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Distracting")
                button.contentTintColor = NSColor.systemRed
            case .custom:
                button.image = NSImage(systemSymbolName: "tag.circle.fill", accessibilityDescription: "Custom")
                button.contentTintColor = NSColor.systemBlue
            }
        } else {
            // User is idle or no activity
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Idle")
            button.contentTintColor = NSColor.systemGray
        }
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    // MARK: - Public Methods
    
    func openSettings() {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        settingsWindow.title = "Productivity Assistant Settings"
        settingsWindow.center()
        settingsWindow.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow.makeKeyAndOrderFront(nil)
    }
    
    func openStatistics() {
        let statisticsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        statisticsWindow.title = "Activity Statistics"
        statisticsWindow.center()
        statisticsWindow.contentView = NSHostingView(rootView: StatisticsView())
        statisticsWindow.makeKeyAndOrderFront(nil)
    }
    
    func openGoals() {
        let goalsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        goalsWindow.title = "Goals & Objectives"
        goalsWindow.center()
        goalsWindow.contentView = NSHostingView(rootView: GoalsView())
        goalsWindow.makeKeyAndOrderFront(nil)
    }
    
    func openHabits() {
        let habitsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        habitsWindow.title = "Habits & Insights"
        habitsWindow.center()
        habitsWindow.contentView = NSHostingView(rootView: HabitsView())
        habitsWindow.makeKeyAndOrderFront(nil)
    }
} 