import Foundation
import Combine

/// Protocol defining the operations for monitoring user activity
protocol ActivityMonitorService {
    /// Starts monitoring user activity
    func startMonitoring() -> AnyPublisher<ActivityRecord, Error>
    
    /// Stops monitoring user activity
    func stopMonitoring()
    
    /// Returns the current activity
    func getCurrentActivity() -> ActivityRecord?
    
    /// Returns whether the monitoring service is active
    var isMonitoring: Bool { get }
    
    /// Returns whether the user is idle
    var isUserIdle: Bool { get }
    
    /// Returns the idle duration threshold in seconds
    var idleThreshold: TimeInterval { get set }
    
    /// Returns a publisher that emits when the user's idle state changes
    var idleStatePublisher: AnyPublisher<Bool, Never> { get }
    
    /// Categorizes an activity
    func categorizeActivity(_ record: ActivityRecord, as category: ActivityCategory)
    
    /// Returns whether the service has accessibility permissions
    var hasAccessibilityPermissions: Bool { get }
    
    /// Requests accessibility permissions
    func requestAccessibilityPermissions()
} 