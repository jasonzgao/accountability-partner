import Foundation
import Combine
import os.log

/// Represents a time period for aggregating activity data
enum TimePeriod {
    case day(Date)
    case week(Date)
    case month(Date)
    case custom(from: Date, to: Date)
    
    var dateInterval: DateInterval {
        switch self {
        case .day(let date):
            return DateInterval(start: date.startOfDay, end: date.endOfDay)
        case .week(let date):
            return DateInterval(start: date.startOfWeek, end: date.endOfWeek)
        case .month(let date):
            return DateInterval(start: date.startOfMonth, end: date.endOfMonth)
        case .custom(let from, let to):
            return DateInterval(start: from, end: to)
        }
    }
    
    var description: String {
        switch self {
        case .day(let date):
            return date.relativeDescription
        case .week:
            return "Week of \(dateInterval.start.formattedString(format: "MMM d"))"
        case .month:
            return dateInterval.start.formattedString(format: "MMMM yyyy")
        case .custom:
            return "\(dateInterval.start.formattedString(format: "MMM d")) - \(dateInterval.end.formattedString(format: "MMM d"))"
        }
    }
}

/// Statistics for activities in a specific time period
struct ActivityStatistics {
    /// The time period for these statistics
    let period: TimePeriod
    
    /// Total time spent (seconds) in each category
    let categoryTimes: [ActivityCategory: TimeInterval]
    
    /// Top applications by usage time
    let topApplications: [(name: String, duration: TimeInterval, category: ActivityCategory)]
    
    /// Top websites by usage time
    let topWebsites: [(host: String, duration: TimeInterval, category: ActivityCategory)]
    
    /// Productivity score (0-100)
    let productivityScore: Int
    
    /// Distraction score (0-100)
    let distractionScore: Int
    
    /// Time spent actively using the computer
    let totalActiveTime: TimeInterval
    
    /// Total tracked time including idle periods
    let totalTrackedTime: TimeInterval
    
    /// Longest productive streak (consecutive productive time)
    let longestProductiveStreak: TimeInterval
    
    /// Current productive streak
    let currentProductiveStreak: TimeInterval
    
    /// Longest distraction-free period
    let longestDistractedPeriod: TimeInterval
    
    /// Activity records used to generate these statistics
    let activityRecords: [ActivityRecord]
}

/// Protocol for a service that provides activity statistics
protocol ActivityStatisticsService {
    /// Gets statistics for a specified time period
    func getStatistics(for period: TimePeriod) -> AnyPublisher<ActivityStatistics, Error>
    
    /// Gets all activities within a time period
    func getActivities(for period: TimePeriod) -> AnyPublisher<[ActivityRecord], Error>
    
    /// Gets the current streak (consecutive productive time)
    func getCurrentStreak() -> AnyPublisher<TimeInterval, Error>
    
    /// Gets statistics about computer usage patterns
    func getUsagePatterns(for period: TimePeriod) -> AnyPublisher<[String: Any], Error>
}

/// Implementation of the ActivityStatisticsService
final class DefaultActivityStatisticsService: ActivityStatisticsService {
    // MARK: - Properties
    
    private let activityRepository: ActivityRecordRepositoryProtocol
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Statistics")
    
    // MARK: - Initialization
    
    init(activityRepository: ActivityRecordRepositoryProtocol) {
        self.activityRepository = activityRepository
    }
    
    // MARK: - Public Methods
    
    func getStatistics(for period: TimePeriod) -> AnyPublisher<ActivityStatistics, Error> {
        return getActivities(for: period)
            .map { [weak self] activities -> ActivityStatistics in
                guard let self = self else {
                    throw NSError(domain: "StatisticsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])
                }
                
                return self.calculateStatistics(activities: activities, period: period)
            }
            .eraseToAnyPublisher()
    }
    
    func getActivities(for period: TimePeriod) -> AnyPublisher<[ActivityRecord], Error> {
        return Future<[ActivityRecord], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "StatisticsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            let interval = period.dateInterval
            
            do {
                let activities = try self.activityRepository.getActivitiesInRange(from: interval.start, to: interval.end)
                promise(.success(activities))
            } catch {
                self.logger.error("Failed to get activities: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getCurrentStreak() -> AnyPublisher<TimeInterval, Error> {
        return Future<TimeInterval, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "StatisticsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            // Get today's activities
            let today = Date()
            
            do {
                let activities = try self.activityRepository.getActivitiesInRange(from: today.startOfDay, to: today)
                    .sorted(by: { $0.startTime > $1.startTime }) // Most recent first
                
                // Calculate the current streak
                let streak = self.calculateCurrentStreak(activities: activities)
                promise(.success(streak))
            } catch {
                self.logger.error("Failed to get current streak: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getUsagePatterns(for period: TimePeriod) -> AnyPublisher<[String: Any], Error> {
        return getActivities(for: period)
            .map { [weak self] activities -> [String: Any] in
                guard let self = self else {
                    throw NSError(domain: "StatisticsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])
                }
                
                return self.analyzeUsagePatterns(activities: activities, period: period)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func calculateStatistics(activities: [ActivityRecord], period: TimePeriod) -> ActivityStatistics {
        // Group activities by category
        var categoryTimes: [ActivityCategory: TimeInterval] = [:]
        var applicationTimes: [String: (duration: TimeInterval, category: ActivityCategory)] = [:]
        var websiteTimes: [String: (duration: TimeInterval, category: ActivityCategory)] = [:]
        var totalActiveTime: TimeInterval = 0
        var longestProductiveStreak: TimeInterval = 0
        var longestDistractedPeriod: TimeInterval = 0
        var currentProductiveStreak: TimeInterval = 0
        
        // Process activities
        for activity in activities {
            guard let duration = activity.durationInSeconds else { continue }
            
            // Update category times
            let category = activity.category
            categoryTimes[category, default: 0] += duration
            
            // Update total active time
            totalActiveTime += duration
            
            // Update application times
            let appName = activity.applicationName
            let appData = applicationTimes[appName, default: (0, category)]
            applicationTimes[appName] = (appData.duration + duration, appData.category)
            
            // If it's a browser tab with a URL, track website time
            if let url = activity.url, let host = url.host {
                let hostData = websiteTimes[host, default: (0, category)]
                websiteTimes[host] = (hostData.duration + duration, hostData.category)
            }
        }
        
        // Calculate streaks
        let sortedActivities = activities.sorted { $0.startTime < $1.startTime }
        var currentStreak: TimeInterval = 0
        
        for i in 0..<sortedActivities.count {
            let activity = sortedActivities[i]
            
            // Skip activities without duration
            guard let duration = activity.durationInSeconds else { continue }
            
            if activity.category == .productive {
                currentStreak += duration
                
                // Update longest productive streak if needed
                if currentStreak > longestProductiveStreak {
                    longestProductiveStreak = currentStreak
                }
                
                // If this is the last activity or the next one doesn't start immediately after,
                // reset the streak counter
                if i == sortedActivities.count - 1 {
                    currentProductiveStreak = currentStreak
                } else if let nextActivity = sortedActivities[safe: i + 1],
                          let activityEnd = activity.endTime,
                          nextActivity.startTime.timeIntervalSince(activityEnd) > 60 { // Gap of more than a minute
                    if i == sortedActivities.count - 2 { // Second to last activity
                        currentProductiveStreak = nextActivity.category == .productive ? currentStreak : 0
                    } else {
                        currentStreak = 0
                    }
                }
            } else {
                // Reset streak counter for non-productive activities
                currentStreak = 0
                
                // Track longest distracted period
                if activity.category == .distracting && duration > longestDistractedPeriod {
                    longestDistractedPeriod = duration
                }
            }
        }
        
        // Sort applications and websites by duration
        let topApplications = applicationTimes.map { (name: $0.key, duration: $0.value.duration, category: $0.value.category) }
            .sorted { $0.duration > $1.duration }
            .prefix(10)
            .map { (name: $0.name, duration: $0.duration, category: $0.category) }
        
        let topWebsites = websiteTimes.map { (host: $0.key, duration: $0.value.duration, category: $0.value.category) }
            .sorted { $0.duration > $1.duration }
            .prefix(10)
            .map { (host: $0.host, duration: $0.duration, category: $0.category) }
        
        // Calculate productivity score
        let productiveTime = categoryTimes[.productive] ?? 0
        let neutralTime = categoryTimes[.neutral] ?? 0
        let distractingTime = categoryTimes[.distracting] ?? 0
        let customTime = categoryTimes[.custom] ?? 0
        
        // Total time accounting for all categories
        let totalCategorizedTime = productiveTime + neutralTime + distractingTime + customTime
        
        // Productivity score: productiveTime / (totalTime - neutralTime) * 100, capped at 100
        let productivityDenominator = max(totalCategorizedTime - neutralTime, 1) // Avoid division by zero
        let rawProductivityScore = (productiveTime / productivityDenominator) * 100
        let productivityScore = min(Int(rawProductivityScore), 100)
        
        // Distraction score: distractingTime / totalTime * 100, capped at 100
        let distractionDenominator = max(totalCategorizedTime, 1) // Avoid division by zero
        let rawDistractionScore = (distractingTime / distractionDenominator) * 100
        let distractionScore = min(Int(rawDistractionScore), 100)
        
        // Total tracked time is the duration of the period
        let totalTrackedTime = period.dateInterval.duration
        
        return ActivityStatistics(
            period: period,
            categoryTimes: categoryTimes,
            topApplications: Array(topApplications),
            topWebsites: Array(topWebsites),
            productivityScore: productivityScore,
            distractionScore: distractionScore,
            totalActiveTime: totalActiveTime,
            totalTrackedTime: totalTrackedTime,
            longestProductiveStreak: longestProductiveStreak,
            currentProductiveStreak: currentProductiveStreak,
            longestDistractedPeriod: longestDistractedPeriod,
            activityRecords: activities
        )
    }
    
    private func calculateCurrentStreak(activities: [ActivityRecord]) -> TimeInterval {
        // Start from most recent and go backwards
        var currentStreak: TimeInterval = 0
        var lastActivity: ActivityRecord?
        
        for activity in activities {
            guard let duration = activity.durationInSeconds else { continue }
            
            if activity.category == .productive {
                // Check if this activity is continuous with the last one
                if let lastActivity = lastActivity,
                   let lastEnd = lastActivity.endTime,
                   activity.startTime.timeIntervalSince(lastEnd) < 60 { // Less than a minute gap
                    currentStreak += duration
                } else if lastActivity == nil {
                    // First activity in the loop
                    currentStreak = duration
                } else {
                    // Break in the streak
                    break
                }
            } else {
                // Non-productive activity breaks the streak
                break
            }
            
            lastActivity = activity
        }
        
        return currentStreak
    }
    
    private func analyzeUsagePatterns(activities: [ActivityRecord], period: TimePeriod) -> [String: Any] {
        // Group activities by hour of day
        var hourlyActivity: [Int: TimeInterval] = [:]
        var productiveHourlyActivity: [Int: TimeInterval] = [:]
        var distractingHourlyActivity: [Int: TimeInterval] = [:]
        
        // Group activities by day of week (1 = Sunday, 7 = Saturday)
        var dailyActivity: [Int: TimeInterval] = [:]
        var productiveDailyActivity: [Int: TimeInterval] = [:]
        var distractingDailyActivity: [Int: TimeInterval] = [:]
        
        // Calendar for date calculations
        let calendar = Calendar.current
        
        for activity in activities {
            guard let duration = activity.durationInSeconds else { continue }
            
            // Get hour and day components
            let hour = calendar.component(.hour, from: activity.startTime)
            let day = calendar.component(.weekday, from: activity.startTime)
            
            // Update hourly activity
            hourlyActivity[hour, default: 0] += duration
            
            // Update daily activity
            dailyActivity[day, default: 0] += duration
            
            // Update by category
            if activity.category == .productive {
                productiveHourlyActivity[hour, default: 0] += duration
                productiveDailyActivity[day, default: 0] += duration
            } else if activity.category == .distracting {
                distractingHourlyActivity[hour, default: 0] += duration
                distractingDailyActivity[day, default: 0] += duration
            }
        }
        
        // Calculate most productive hours and days
        let mostProductiveHour = productiveHourlyActivity.max { $0.value < $1.value }?.key ?? 0
        let mostProductiveDay = productiveDailyActivity.max { $0.value < $1.value }?.key ?? 0
        
        // Calculate most distracting hours and days
        let mostDistractingHour = distractingHourlyActivity.max { $0.value < $1.value }?.key ?? 0
        let mostDistractingDay = distractingDailyActivity.max { $0.value < $1.value }?.key ?? 0
        
        // Calculate peak productivity time
        let productivityByHour = hourlyActivity.mapValues { totalTime -> Double in
            let productiveTime = productiveHourlyActivity[hourlyActivity.first!.key] ?? 0
            return totalTime > 0 ? productiveTime / totalTime : 0
        }
        let peakProductivityHour = productivityByHour.max { $0.value < $1.value }?.key ?? 0
        
        // Build result dictionary
        return [
            "hourlyActivity": hourlyActivity,
            "dailyActivity": dailyActivity,
            "productiveHourlyActivity": productiveHourlyActivity,
            "distractingHourlyActivity": distractingHourlyActivity,
            "productiveDailyActivity": productiveDailyActivity,
            "distractingDailyActivity": distractingDailyActivity,
            "mostProductiveHour": mostProductiveHour,
            "mostProductiveDay": mostProductiveDay,
            "mostDistractingHour": mostDistractingHour,
            "mostDistractingDay": mostDistractingDay,
            "peakProductivityHour": peakProductivityHour
        ]
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 