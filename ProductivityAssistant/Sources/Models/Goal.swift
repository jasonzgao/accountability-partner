import Foundation
import GRDB

/// Represents the type of goal
enum GoalType: String, Codable, CaseIterable {
    case timeSpent = "time_spent"
    case timeLimit = "time_limit"
    case activityCount = "activity_count"
    case activityRatio = "activity_ratio"
    case completion = "completion"
    case custom = "custom"
    
    var description: String {
        switch self {
        case .timeSpent:
            return "Time Spent"
        case .timeLimit:
            return "Time Limit"
        case .activityCount:
            return "Activity Count"
        case .activityRatio:
            return "Activity Ratio"
        case .completion:
            return "Completion"
        case .custom:
            return "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .timeSpent:
            return "clock"
        case .timeLimit:
            return "timer"
        case .activityCount:
            return "number"
        case .activityRatio:
            return "percent"
        case .completion:
            return "checkmark"
        case .custom:
            return "star"
        }
    }
}

/// Represents the frequency at which a goal is evaluated
enum GoalFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekdays = "weekdays"
    case weekends = "weekends"
    case weekly = "weekly"
    case monthly = "monthly"
    case custom = "custom"
    
    var description: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom"
        }
    }
    
    func nextDue(from date: Date) -> Date {
        let calendar = Calendar.current
        
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let weekday = calendar.component(.weekday, from: nextDate)
            
            // If next date is Saturday (7) or Sunday (1), move to Monday (2)
            if weekday == 1 {
                // Sunday to Monday
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
            } else if weekday == 7 {
                // Saturday to Monday
                nextDate = calendar.date(byAdding: .day, value: 2, to: nextDate) ?? nextDate
            }
            
            return nextDate
        case .weekends:
            var nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let weekday = calendar.component(.weekday, from: nextDate)
            
            // If not Saturday (7) or Sunday (1), move to next Saturday
            if weekday != 1 && weekday != 7 {
                // Calculate days until Saturday
                let daysUntilSaturday = 7 - weekday
                nextDate = calendar.date(byAdding: .day, value: daysUntilSaturday, to: nextDate) ?? nextDate
            }
            
            return nextDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .custom:
            // For custom frequency, we'll need additional information
            // For now, default to 7 days
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        }
    }
    
    func isActiveOn(date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        
        switch self {
        case .daily:
            return true
        case .weekdays:
            // Weekdays are Monday (2) to Friday (6)
            return weekday >= 2 && weekday <= 6
        case .weekends:
            // Weekend is Saturday (7) and Sunday (1)
            return weekday == 1 || weekday == 7
        case .weekly, .monthly:
            // These are larger periods that include any day
            return true
        case .custom:
            // Would require additional information to determine
            return true
        }
    }
}

/// Represents a target or objective to achieve
struct Goal: Codable, Identifiable {
    let id: String
    var title: String
    var description: String?
    var type: GoalType
    var frequency: GoalFrequency
    var target: Double
    var currentProgress: Double
    var unit: String
    var startDate: Date
    var endDate: Date?
    var categoryFilter: String?
    var applicationFilter: String?
    var urlFilter: String?
    var lastUpdated: Date
    var isActive: Bool
    var daysCompleted: Int
    var streak: Int
    var customFrequencyDays: [Int]?
    var reminderTime: Date?
    var isArchived: Bool
    
    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        type: GoalType,
        frequency: GoalFrequency,
        target: Double,
        currentProgress: Double = 0.0,
        unit: String,
        startDate: Date = Date(),
        endDate: Date? = nil,
        categoryFilter: String? = nil,
        applicationFilter: String? = nil,
        urlFilter: String? = nil,
        lastUpdated: Date = Date(),
        isActive: Bool = true,
        daysCompleted: Int = 0,
        streak: Int = 0,
        customFrequencyDays: [Int]? = nil,
        reminderTime: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.frequency = frequency
        self.target = target
        self.currentProgress = currentProgress
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.categoryFilter = categoryFilter
        self.applicationFilter = applicationFilter
        self.urlFilter = urlFilter
        self.lastUpdated = lastUpdated
        self.isActive = isActive
        self.daysCompleted = daysCompleted
        self.streak = streak
        self.customFrequencyDays = customFrequencyDays
        self.reminderTime = reminderTime
        self.isArchived = isArchived
    }
    
    var progressPercentage: Double {
        guard target > 0 else { return 0 }
        return min(currentProgress / target, 1.0)
    }
    
    var isCompleted: Bool {
        return currentProgress >= target
    }
    
    var displayUnit: String {
        switch type {
        case .timeSpent, .timeLimit:
            return "hours"
        case .activityCount:
            return "count"
        case .activityRatio:
            return "%"
        case .completion:
            return "tasks"
        case .custom:
            return unit
        }
    }
    
    var isExpired: Bool {
        guard let endDate = endDate else { return false }
        return Date() > endDate
    }
}

/// Database record for storing goals
struct GoalRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static var databaseTableName: String = "goals"
    
    let id: String
    let title: String
    let description: String?
    let type: String
    let frequency: String
    let target: Double
    let currentProgress: Double
    let unit: String
    let startDate: Date
    let endDate: Date?
    let categoryFilter: String?
    let applicationFilter: String?
    let urlFilter: String?
    let lastUpdated: Date
    let isActive: Bool
    let daysCompleted: Int
    let streak: Int
    let customFrequencyDays: String?
    let reminderTime: Date?
    let isArchived: Bool
    
    init(from goal: Goal) {
        self.id = goal.id
        self.title = goal.title
        self.description = goal.description
        self.type = goal.type.rawValue
        self.frequency = goal.frequency.rawValue
        self.target = goal.target
        self.currentProgress = goal.currentProgress
        self.unit = goal.unit
        self.startDate = goal.startDate
        self.endDate = goal.endDate
        self.categoryFilter = goal.categoryFilter
        self.applicationFilter = goal.applicationFilter
        self.urlFilter = goal.urlFilter
        self.lastUpdated = goal.lastUpdated
        self.isActive = goal.isActive
        self.daysCompleted = goal.daysCompleted
        self.streak = goal.streak
        
        if let days = goal.customFrequencyDays {
            self.customFrequencyDays = days.map { String($0) }.joined(separator: ",")
        } else {
            self.customFrequencyDays = nil
        }
        
        self.reminderTime = goal.reminderTime
        self.isArchived = goal.isArchived
    }
    
    func toModel() -> Goal {
        var customDays: [Int]?
        if let daysString = customFrequencyDays {
            customDays = daysString.split(separator: ",").compactMap { Int(String($0)) }
        }
        
        return Goal(
            id: id,
            title: title,
            description: description,
            type: GoalType(rawValue: type) ?? .custom,
            frequency: GoalFrequency(rawValue: frequency) ?? .daily,
            target: target,
            currentProgress: currentProgress,
            unit: unit,
            startDate: startDate,
            endDate: endDate,
            categoryFilter: categoryFilter,
            applicationFilter: applicationFilter,
            urlFilter: urlFilter,
            lastUpdated: lastUpdated,
            isActive: isActive,
            daysCompleted: daysCompleted,
            streak: streak,
            customFrequencyDays: customDays,
            reminderTime: reminderTime,
            isArchived: isArchived
        )
    }
}

/// Records a historical progress entry for a goal
struct GoalProgressRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static var databaseTableName: String = "goal_progress"
    
    let id: String
    let goalId: String
    let date: Date
    let progressValue: Double
    let isCompleted: Bool
    
    init(
        id: String = UUID().uuidString,
        goalId: String,
        date: Date = Date(),
        progressValue: Double,
        isCompleted: Bool
    ) {
        self.id = id
        self.goalId = goalId
        self.date = date
        self.progressValue = progressValue
        self.isCompleted = isCompleted
    }
} 
 