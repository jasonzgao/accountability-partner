import Foundation
import Combine
import os.log

/// Protocol for tracking and managing goals
protocol GoalTrackingService {
    /// Gets all active goals
    func getActiveGoals() -> AnyPublisher<[Goal], Error>
    
    /// Gets a specific goal by ID
    func getGoal(id: String) -> AnyPublisher<Goal?, Error>
    
    /// Creates a new goal
    func createGoal(_ goal: Goal) -> AnyPublisher<Goal, Error>
    
    /// Updates an existing goal
    func updateGoal(_ goal: Goal) -> AnyPublisher<Goal, Error>
    
    /// Deletes a goal
    func deleteGoal(id: String) -> AnyPublisher<Bool, Error>
    
    /// Archives a goal
    func archiveGoal(id: String) -> AnyPublisher<Bool, Error>
    
    /// Updates progress for a goal
    func updateProgress(goalId: String, progress: Double) -> AnyPublisher<Goal, Error>
    
    /// Gets progress history for a goal
    func getProgressHistory(goalId: String) -> AnyPublisher<[GoalProgressRecord], Error>
    
    /// Gets goals that match the given filter
    func getGoals(matching filter: GoalFilter) -> AnyPublisher<[Goal], Error>
    
    /// Gets goals related to a specific activity
    func getGoalsForActivity(_ activity: ActivityRecord) -> AnyPublisher<[Goal], Error>
    
    /// Calculates progress for all active goals based on tracked activities
    func calculateProgressForAllGoals() -> AnyPublisher<Int, Error>
    
    /// Publisher for all goal updates
    var goalsPublisher: AnyPublisher<[Goal], Error> { get }
}

/// Implementation of the goal tracking service
final class DefaultGoalTrackingService: GoalTrackingService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "GoalTracking")
    private let goalRepository: GoalRepositoryProtocol
    private let activityRepository: ActivityRecordRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    var goalsPublisher: AnyPublisher<[Goal], Error> {
        return goalRepository.goalsPublisher
    }
    
    // MARK: - Initialization
    
    init(
        goalRepository: GoalRepositoryProtocol,
        activityRepository: ActivityRecordRepositoryProtocol
    ) {
        self.goalRepository = goalRepository
        self.activityRepository = activityRepository
        
        // Setup daily progress calculation
        setupDailyProgressCalculation()
    }
    
    // MARK: - Public Methods
    
    func getActiveGoals() -> AnyPublisher<[Goal], Error> {
        return Future<[Goal], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                let goals = try self.goalRepository.getActiveGoals()
                promise(.success(goals))
            } catch {
                self.logger.error("Failed to get active goals: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getGoal(id: String) -> AnyPublisher<Goal?, Error> {
        return Future<Goal?, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                let goal = try self.goalRepository.getGoal(id: id)
                promise(.success(goal))
            } catch {
                self.logger.error("Failed to get goal \(id): \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func createGoal(_ goal: Goal) -> AnyPublisher<Goal, Error> {
        return Future<Goal, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                try self.goalRepository.saveGoal(goal)
                promise(.success(goal))
            } catch {
                self.logger.error("Failed to create goal: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func updateGoal(_ goal: Goal) -> AnyPublisher<Goal, Error> {
        return Future<Goal, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                try self.goalRepository.saveGoal(goal)
                promise(.success(goal))
            } catch {
                self.logger.error("Failed to update goal: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteGoal(id: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                try self.goalRepository.deleteGoal(id: id)
                promise(.success(true))
            } catch {
                self.logger.error("Failed to delete goal \(id): \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func archiveGoal(id: String) -> AnyPublisher<Bool, Error> {
        return getGoal(id: id)
            .flatMap { [weak self] goal -> AnyPublisher<Bool, Error> in
                guard let self = self, var goal = goal else {
                    return Fail(error: GoalTrackingError.goalNotFound).eraseToAnyPublisher()
                }
                
                goal.isArchived = true
                
                return Future<Bool, Error> { promise in
                    do {
                        try self.goalRepository.saveGoal(goal)
                        promise(.success(true))
                    } catch {
                        self.logger.error("Failed to archive goal \(id): \(error.localizedDescription)")
                        promise(.failure(error))
                    }
                }
                .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    func updateProgress(goalId: String, progress: Double) -> AnyPublisher<Goal, Error> {
        return Future<Goal, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                try self.goalRepository.updateGoalProgress(id: goalId, progress: progress)
                
                if let updatedGoal = try self.goalRepository.getGoal(id: goalId) {
                    promise(.success(updatedGoal))
                } else {
                    promise(.failure(GoalTrackingError.goalNotFound))
                }
            } catch {
                self.logger.error("Failed to update progress for goal \(goalId): \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getProgressHistory(goalId: String) -> AnyPublisher<[GoalProgressRecord], Error> {
        return Future<[GoalProgressRecord], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                let records = try self.goalRepository.getGoalProgressHistory(goalId: goalId)
                promise(.success(records))
            } catch {
                self.logger.error("Failed to get progress history for goal \(goalId): \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getGoals(matching filter: GoalFilter) -> AnyPublisher<[Goal], Error> {
        return Future<[Goal], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            do {
                let goals = try self.goalRepository.getGoals(matching: filter)
                promise(.success(goals))
            } catch {
                self.logger.error("Failed to get goals with filter: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getGoalsForActivity(_ activity: ActivityRecord) -> AnyPublisher<[Goal], Error> {
        // Create a filter for this activity
        let filter = GoalFilter(
            isActive: true,
            isArchived: false,
            categoryId: activity.category.rawValue,
            applicationName: activity.applicationName
        )
        
        return getGoals(matching: filter)
            .eraseToAnyPublisher()
    }
    
    func calculateProgressForAllGoals() -> AnyPublisher<Int, Error> {
        return getActiveGoals()
            .flatMap { [weak self] goals -> AnyPublisher<Int, Error> in
                guard let self = self else {
                    return Fail(error: GoalTrackingError.serviceNotAvailable).eraseToAnyPublisher()
                }
                
                // No goals to update
                if goals.isEmpty {
                    return Just(0).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
                return self.calculateProgressForGoals(goals)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func calculateProgressForGoals(_ goals: [Goal]) -> AnyPublisher<Int, Error> {
        return Future<Int, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(GoalTrackingError.serviceNotAvailable))
                return
            }
            
            var updatedCount = 0
            
            for goal in goals {
                do {
                    // Calculate progress based on goal type
                    let newProgress = try self.calculateProgress(for: goal)
                    
                    // Only update if progress has changed
                    if abs(newProgress - goal.currentProgress) > 0.01 {
                        try self.goalRepository.updateGoalProgress(id: goal.id, progress: newProgress)
                        updatedCount += 1
                    }
                } catch {
                    self.logger.error("Failed to calculate progress for goal \(goal.id): \(error.localizedDescription)")
                    // Continue with other goals
                }
            }
            
            promise(.success(updatedCount))
        }
        .eraseToAnyPublisher()
    }
    
    private func calculateProgress(for goal: Goal) throws -> Double {
        let now = Date()
        let calendar = Calendar.current
        
        // Determine the time range based on frequency
        var startDate: Date
        var endDate: Date = now
        
        switch goal.frequency {
        case .daily:
            startDate = calendar.startOfDay(for: now)
        case .weekdays:
            // If it's a weekend, use the last weekday
            let weekday = calendar.component(.weekday, from: now)
            if weekday == 1 || weekday == 7 { // Sunday (1) or Saturday (7)
                let daysToSubtract = weekday == 1 ? 2 : 1 // Subtract 2 days for Sunday, 1 for Saturday
                startDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: now)) ?? now
            } else {
                startDate = calendar.startOfDay(for: now)
            }
        case .weekends:
            // If it's a weekday, use the last weekend
            let weekday = calendar.component(.weekday, from: now)
            if weekday >= 2 && weekday <= 6 { // Monday to Friday
                let daysToSubtract = weekday - 1
                startDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: now)) ?? now
            } else {
                startDate = calendar.startOfDay(for: now)
            }
        case .weekly:
            startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            startDate = calendar.date(from: components) ?? now
        case .custom:
            // Default to last 7 days for custom
            startDate = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        }
        
        switch goal.type {
        case .timeSpent:
            return try calculateTimeSpent(startDate: startDate, endDate: endDate, goal: goal)
        case .timeLimit:
            return try calculateTimeLimit(startDate: startDate, endDate: endDate, goal: goal)
        case .activityCount:
            return try calculateActivityCount(startDate: startDate, endDate: endDate, goal: goal)
        case .activityRatio:
            return try calculateActivityRatio(startDate: startDate, endDate: endDate, goal: goal)
        case .completion:
            // The completion type requires external integration, so we return the existing value
            return goal.currentProgress
        case .custom:
            // Custom goals may have their own calculation logic
            return goal.currentProgress
        }
    }
    
    private func calculateTimeSpent(startDate: Date, endDate: Date, goal: Goal) throws -> Double {
        var query = "SELECT SUM(duration) FROM activity_records WHERE timestamp >= ? AND timestamp <= ?"
        var arguments: [DatabaseValueConvertible] = [startDate, endDate]
        
        // Add filters if present
        if let categoryFilter = goal.categoryFilter {
            query += " AND category = ?"
            arguments.append(categoryFilter)
        }
        
        if let appFilter = goal.applicationFilter {
            query += " AND application_name = ?"
            arguments.append(appFilter)
        }
        
        if let urlFilter = goal.urlFilter {
            query += " AND url LIKE ?"
            arguments.append("%\(urlFilter)%")
        }
        
        let totalDuration = try activityRepository.executeTimeQuery(query: query, arguments: arguments)
        
        // Convert seconds to hours if that's the unit
        if goal.unit.lowercased() == "hours" {
            return totalDuration / 3600.0
        } else {
            return totalDuration / 60.0 // Minutes
        }
    }
    
    private func calculateTimeLimit(startDate: Date, endDate: Date, goal: Goal) throws -> Double {
        // Time limit is similar to time spent, but we invert the progress
        // Higher progress means getting closer to the limit
        let timeSpent = try calculateTimeSpent(startDate: startDate, endDate: endDate, goal: goal)
        
        // For time limit, we want to return how close we are to the limit
        // If we've exceeded the limit, return the full amount
        if timeSpent >= goal.target {
            return goal.target
        }
        
        return timeSpent
    }
    
    private func calculateActivityCount(startDate: Date, endDate: Date, goal: Goal) throws -> Double {
        var query = "SELECT COUNT(*) FROM activity_records WHERE timestamp >= ? AND timestamp <= ?"
        var arguments: [DatabaseValueConvertible] = [startDate, endDate]
        
        // Add filters if present
        if let categoryFilter = goal.categoryFilter {
            query += " AND category = ?"
            arguments.append(categoryFilter)
        }
        
        if let appFilter = goal.applicationFilter {
            query += " AND application_name = ?"
            arguments.append(appFilter)
        }
        
        if let urlFilter = goal.urlFilter {
            query += " AND url LIKE ?"
            arguments.append("%\(urlFilter)%")
        }
        
        return try activityRepository.executeCountQuery(query: query, arguments: arguments)
    }
    
    private func calculateActivityRatio(startDate: Date, endDate: Date, goal: Goal) throws -> Double {
        // For activity ratio, we need both the filtered activities and the total activities
        
        // First, get the count of filtered activities
        var filteredQuery = "SELECT COUNT(*) FROM activity_records WHERE timestamp >= ? AND timestamp <= ?"
        var filteredArguments: [DatabaseValueConvertible] = [startDate, endDate]
        
        // Add filters if present
        if let categoryFilter = goal.categoryFilter {
            filteredQuery += " AND category = ?"
            filteredArguments.append(categoryFilter)
        }
        
        if let appFilter = goal.applicationFilter {
            filteredQuery += " AND application_name = ?"
            filteredArguments.append(appFilter)
        }
        
        if let urlFilter = goal.urlFilter {
            filteredQuery += " AND url LIKE ?"
            filteredArguments.append("%\(urlFilter)%")
        }
        
        let filteredCount = try activityRepository.executeCountQuery(query: filteredQuery, arguments: filteredArguments)
        
        // Now get the total count
        let totalQuery = "SELECT COUNT(*) FROM activity_records WHERE timestamp >= ? AND timestamp <= ?"
        let totalArguments: [DatabaseValueConvertible] = [startDate, endDate]
        let totalCount = try activityRepository.executeCountQuery(query: totalQuery, arguments: totalArguments)
        
        // Avoid division by zero
        guard totalCount > 0 else {
            return 0
        }
        
        // Calculate the ratio as a percentage
        return (filteredCount / totalCount) * 100.0
    }
    
    private func setupDailyProgressCalculation() {
        // Setup a timer to calculate progress regularly
        Timer.publish(every: 3600, on: .main, in: .common) // hourly
            .autoconnect()
            .sink { [weak self] _ in
                self?.calculateProgressForAllGoals()
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                self?.logger.error("Failed to calculate goals: \(error.localizedDescription)")
                            }
                        },
                        receiveValue: { updatedCount in
                            self?.logger.info("Updated progress for \(updatedCount) goals")
                        }
                    )
                    .store(in: &self!.cancellables)
            }
            .store(in: &cancellables)
    }
}

enum GoalTrackingError: Error {
    case serviceNotAvailable
    case goalNotFound
    case invalidGoalType
    case calculationFailed
    
    var localizedDescription: String {
        switch self {
        case .serviceNotAvailable:
            return "Goal tracking service is not available"
        case .goalNotFound:
            return "Goal not found"
        case .invalidGoalType:
            return "Invalid goal type"
        case .calculationFailed:
            return "Failed to calculate goal progress"
        }
    }
} 
 