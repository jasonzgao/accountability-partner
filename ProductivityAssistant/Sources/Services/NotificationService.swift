import Foundation
import UserNotifications
import Combine
import os.log

/// Represents a notification type in the application
enum NotificationType: String, CaseIterable {
    case productivityAlert = "productivity_alert"
    case distractionAlert = "distraction_alert"
    case goalReminder = "goal_reminder"
    case goalAchieved = "goal_achieved"
    case dailySummary = "daily_summary"
    case weeklySummary = "weekly_summary"
    case habitInsight = "habit_insight"
    case focusTime = "focus_time"
    case idleReturn = "idle_return"
    case systemAlert = "system_alert"
    
    var displayName: String {
        switch self {
        case .productivityAlert: return "Productivity Alert"
        case .distractionAlert: return "Distraction Alert"
        case .goalReminder: return "Goal Reminder"
        case .goalAchieved: return "Goal Achievement"
        case .dailySummary: return "Daily Summary"
        case .weeklySummary: return "Weekly Summary"
        case .habitInsight: return "Habit Insight"
        case .focusTime: return "Focus Time"
        case .idleReturn: return "Idle Return"
        case .systemAlert: return "System Alert"
        }
    }
    
    var iconName: String {
        switch self {
        case .productivityAlert: return "chart.bar.fill"
        case .distractionAlert: return "exclamationmark.triangle.fill"
        case .goalReminder: return "bell.fill"
        case .goalAchieved: return "trophy.fill"
        case .dailySummary: return "calendar.badge.clock"
        case .weeklySummary: return "calendar.badge.clock"
        case .habitInsight: return "lightbulb.fill"
        case .focusTime: return "timer"
        case .idleReturn: return "person.fill"
        case .systemAlert: return "gear"
        }
    }
}

/// Represents a notification in the application
struct AppNotification: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let title: String
    let body: String
    let timestamp: Date
    let isRead: Bool
    let actionURL: URL?
    let relatedEntityId: String?
    let additionalData: [String: String]?
    
    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        title: String,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        actionURL: URL? = nil,
        relatedEntityId: String? = nil,
        additionalData: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.actionURL = actionURL
        self.relatedEntityId = relatedEntityId
        self.additionalData = additionalData
    }
    
    /// Returns a copy of this notification marked as read
    func markAsRead() -> AppNotification {
        return AppNotification(
            id: id,
            type: type,
            title: title,
            body: body,
            timestamp: timestamp,
            isRead: true,
            actionURL: actionURL,
            relatedEntityId: relatedEntityId,
            additionalData: additionalData
        )
    }
}

/// Protocol for notification service
protocol NotificationService {
    /// Sends a notification
    func sendNotification(_ notification: AppNotification) -> AnyPublisher<Bool, Error>
    
    /// Schedules a notification for future delivery
    func scheduleNotification(_ notification: AppNotification, deliveryDate: Date) -> AnyPublisher<Bool, Error>
    
    /// Gets all notifications
    func getAllNotifications() -> AnyPublisher<[AppNotification], Error>
    
    /// Gets unread notifications
    func getUnreadNotifications() -> AnyPublisher<[AppNotification], Error>
    
    /// Gets notifications by type
    func getNotifications(ofType type: NotificationType) -> AnyPublisher<[AppNotification], Error>
    
    /// Marks a notification as read
    func markAsRead(id: String) -> AnyPublisher<Bool, Error>
    
    /// Marks all notifications as read
    func markAllAsRead() -> AnyPublisher<Bool, Error>
    
    /// Deletes a notification
    func deleteNotification(id: String) -> AnyPublisher<Bool, Error>
    
    /// Deletes all notifications
    func deleteAllNotifications() -> AnyPublisher<Bool, Error>
    
    /// Checks if notifications are enabled
    var areNotificationsEnabled: Bool { get }
    
    /// Requests notification permissions if not already granted
    func requestNotificationPermissions() -> AnyPublisher<Bool, Error>
    
    /// Gets notification settings for a specific type
    func getNotificationSettings(for type: NotificationType) -> Bool
    
    /// Updates notification settings for a specific type
    func updateNotificationSettings(for type: NotificationType, enabled: Bool)
    
    /// Publisher for notification updates
    var notificationsPublisher: AnyPublisher<[AppNotification], Never> { get }
    
    /// Publisher for unread count updates
    var unreadCountPublisher: AnyPublisher<Int, Never> { get }
}

/// Implementation of the notification service
final class DefaultNotificationService: NotificationService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Notifications")
    private let userDefaults: UserDefaults
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private var notifications: [AppNotification] = []
    private let notificationsSubject = CurrentValueSubject<[AppNotification], Never>([])
    private let unreadCountSubject = CurrentValueSubject<Int, Never>(0)
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let savedNotifications = "savedNotifications"
        static let notificationSettings = "notificationSettings"
    }
    
    // MARK: - Public Properties
    
    var notificationsPublisher: AnyPublisher<[AppNotification], Never> {
        return notificationsSubject.eraseToAnyPublisher()
    }
    
    var unreadCountPublisher: AnyPublisher<Int, Never> {
        return unreadCountSubject.eraseToAnyPublisher()
    }
    
    var areNotificationsEnabled: Bool {
        var enabled = false
        
        let semaphore = DispatchSemaphore(value: 0)
        
        notificationCenter.getNotificationSettings { settings in
            enabled = settings.authorizationStatus == .authorized
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        return enabled
    }
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Load saved notifications
        loadSavedNotifications()
        
        // Setup notification observers
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    func sendNotification(_ notification: AppNotification) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            // Add to internal notifications list
            self.addNotification(notification)
            
            // Check if we should show a system notification
            if self.getNotificationSettings(for: notification.type) {
                self.showSystemNotification(notification) { success in
                    if success {
                        promise(.success(true))
                    } else {
                        promise(.failure(NotificationError.deliveryFailed))
                    }
                }
            } else {
                // Just add to our internal list without showing a system notification
                promise(.success(true))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func scheduleNotification(_ notification: AppNotification, deliveryDate: Date) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            // Check if we should schedule a system notification
            if self.getNotificationSettings(for: notification.type) {
                self.scheduleSystemNotification(notification, deliveryDate: deliveryDate) { success in
                    if success {
                        promise(.success(true))
                    } else {
                        promise(.failure(NotificationError.schedulingFailed))
                    }
                }
            } else {
                // Just return success without scheduling
                promise(.success(true))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getAllNotifications() -> AnyPublisher<[AppNotification], Error> {
        return Just(notifications)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getUnreadNotifications() -> AnyPublisher<[AppNotification], Error> {
        let unreadNotifications = notifications.filter { !$0.isRead }
        return Just(unreadNotifications)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getNotifications(ofType type: NotificationType) -> AnyPublisher<[AppNotification], Error> {
        let filteredNotifications = notifications.filter { $0.type == type }
        return Just(filteredNotifications)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func markAsRead(id: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            if let index = self.notifications.firstIndex(where: { $0.id == id }) {
                let updatedNotification = self.notifications[index].markAsRead()
                self.notifications[index] = updatedNotification
                
                // Update subjects
                self.notificationsSubject.send(self.notifications)
                self.updateUnreadCount()
                
                // Save to UserDefaults
                self.saveNotifications()
                
                promise(.success(true))
            } else {
                promise(.failure(NotificationError.notificationNotFound))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func markAllAsRead() -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            // Mark all as read
            self.notifications = self.notifications.map { $0.markAsRead() }
            
            // Update subjects
            self.notificationsSubject.send(self.notifications)
            self.updateUnreadCount()
            
            // Save to UserDefaults
            self.saveNotifications()
            
            promise(.success(true))
        }
        .eraseToAnyPublisher()
    }
    
    func deleteNotification(id: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            if let index = self.notifications.firstIndex(where: { $0.id == id }) {
                self.notifications.remove(at: index)
                
                // Update subjects
                self.notificationsSubject.send(self.notifications)
                self.updateUnreadCount()
                
                // Save to UserDefaults
                self.saveNotifications()
                
                promise(.success(true))
            } else {
                promise(.failure(NotificationError.notificationNotFound))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteAllNotifications() -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            // Clear all notifications
            self.notifications.removeAll()
            
            // Update subjects
            self.notificationsSubject.send(self.notifications)
            self.updateUnreadCount()
            
            // Save to UserDefaults
            self.saveNotifications()
            
            promise(.success(true))
        }
        .eraseToAnyPublisher()
    }
    
    func requestNotificationPermissions() -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotificationError.serviceUnavailable))
                return
            }
            
            self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
                    promise(.failure(error))
                } else {
                    self.logger.info("Notification permissions \(granted ? "granted" : "denied")")
                    promise(.success(granted))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getNotificationSettings(for type: NotificationType) -> Bool {
        let settings = userDefaults.dictionary(forKey: UserDefaultsKeys.notificationSettings) as? [String: Bool] ?? [:]
        return settings[type.rawValue] ?? true // Default to enabled
    }
    
    func updateNotificationSettings(for type: NotificationType, enabled: Bool) {
        var settings = userDefaults.dictionary(forKey: UserDefaultsKeys.notificationSettings) as? [String: Bool] ?? [:]
        settings[type.rawValue] = enabled
        userDefaults.set(settings, forKey: UserDefaultsKeys.notificationSettings)
    }
    
    // MARK: - Private Methods
    
    private func loadSavedNotifications() {
        if let notificationsData = userDefaults.data(forKey: UserDefaultsKeys.savedNotifications) {
            do {
                notifications = try JSONDecoder().decode([AppNotification].self, from: notificationsData)
                notificationsSubject.send(notifications)
                updateUnreadCount()
                logger.info("Loaded \(notifications.count) saved notifications")
            } catch {
                logger.error("Failed to decode saved notifications: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveNotifications() {
        do {
            let data = try JSONEncoder().encode(notifications)
            userDefaults.set(data, forKey: UserDefaultsKeys.savedNotifications)
            logger.info("Saved \(notifications.count) notifications")
        } catch {
            logger.error("Failed to encode notifications: \(error.localizedDescription)")
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for delivered notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeliveredNotification(_:)),
            name: NSNotification.Name("UNNotificationDelivered"),
            object: nil
        )
        
        // Listen for notification responses
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationResponse(_:)),
            name: NSNotification.Name("UNNotificationResponse"),
            object: nil
        )
    }
    
    @objc private func handleDeliveredNotification(_ notification: Notification) {
        // Handle delivered notification
        if let userInfo = notification.userInfo,
           let notificationId = userInfo["notificationId"] as? String {
            logger.debug("Notification delivered: \(notificationId)")
        }
    }
    
    @objc private func handleNotificationResponse(_ notification: Notification) {
        // Handle notification response
        if let userInfo = notification.userInfo,
           let notificationId = userInfo["notificationId"] as? String,
           let actionIdentifier = userInfo["actionIdentifier"] as? String {
            logger.debug("Notification response: \(notificationId), action: \(actionIdentifier)")
            
            // Mark as read when user interacts with it
            _ = markAsRead(id: notificationId)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
        }
    }
    
    private func addNotification(_ notification: AppNotification) {
        // Add to the beginning of the list (newest first)
        notifications.insert(notification, at: 0)
        
        // Limit to 100 notifications
        if notifications.count > 100 {
            notifications = Array(notifications.prefix(100))
        }
        
        // Update subjects
        notificationsSubject.send(notifications)
        updateUnreadCount()
        
        // Save to UserDefaults
        saveNotifications()
    }
    
    private func updateUnreadCount() {
        let unreadCount = notifications.filter { !$0.isRead }.count
        unreadCountSubject.send(unreadCount)
    }
    
    private func showSystemNotification(_ notification: AppNotification, completion: @escaping (Bool) -> Void) {
        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = UNNotificationSound.default
        
        // Add the notification ID to the user info
        content.userInfo = ["notificationId": notification.id]
        
        // Add any additional data
        if let additionalData = notification.additionalData {
            for (key, value) in additionalData {
                content.userInfo[key] = value
            }
        }
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        // Add the request to the notification center
        notificationCenter.add(request) { error in
            if let error = error {
                self.logger.error("Failed to show notification: \(error.localizedDescription)")
                completion(false)
            } else {
                self.logger.debug("Notification shown: \(notification.id)")
                completion(true)
            }
        }
    }
    
    private func scheduleSystemNotification(_ notification: AppNotification, deliveryDate: Date, completion: @escaping (Bool) -> Void) {
        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = UNNotificationSound.default
        
        // Add the notification ID to the user info
        content.userInfo = ["notificationId": notification.id]
        
        // Add any additional data
        if let additionalData = notification.additionalData {
            for (key, value) in additionalData {
                content.userInfo[key] = value
            }
        }
        
        // Create the trigger
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: deliveryDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
        
        // Add the request to the notification center
        notificationCenter.add(request) { error in
            if let error = error {
                self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
                completion(false)
            } else {
                self.logger.debug("Notification scheduled: \(notification.id) for \(deliveryDate)")
                completion(true)
            }
        }
    }
}

enum NotificationError: Error {
    case serviceUnavailable
    case notificationNotFound
    case deliveryFailed
    case schedulingFailed
    case permissionDenied
    
    var localizedDescription: String {
        switch self {
        case .serviceUnavailable:
            return "Notification service is not available"
        case .notificationNotFound:
            return "Notification not found"
        case .deliveryFailed:
            return "Failed to deliver notification"
        case .schedulingFailed:
            return "Failed to schedule notification"
        case .permissionDenied:
            return "Notification permission denied"
        }
    }
} 
 