import Foundation
import Combine
import os.log

/// Represents a detected habit pattern
struct HabitPattern: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let applicationName: String?
    let category: ActivityCategory
    let timeOfDay: TimeOfDay
    let daysOfWeek: [Int]
    let averageDuration: TimeInterval
    let consistency: Double // 0.0 to 1.0
    let firstDetected: Date
    let lastObserved: Date
    let occurrences: Int
    
    enum TimeOfDay: String, Codable, CaseIterable {
        case earlyMorning = "early_morning" // 5am-8am
        case morning = "morning" // 8am-12pm
        case afternoon = "afternoon" // 12pm-5pm
        case evening = "evening" // 5pm-9pm
        case night = "night" // 9pm-12am
        case lateNight = "late_night" // 12am-5am
        
        var description: String {
            switch self {
            case .earlyMorning: return "Early Morning (5am-8am)"
            case .morning: return "Morning (8am-12pm)"
            case .afternoon: return "Afternoon (12pm-5pm)"
            case .evening: return "Evening (5pm-9pm)"
            case .night: return "Night (9pm-12am)"
            case .lateNight: return "Late Night (12am-5am)"
            }
        }
        
        static func fromHour(_ hour: Int) -> TimeOfDay {
            switch hour {
            case 5..<8: return .earlyMorning
            case 8..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            case 21..<24: return .night
            default: return .lateNight
            }
        }
    }
    
    var isProductiveHabit: Bool {
        return category == .productive
    }
    
    var isDistractingHabit: Bool {
        return category == .distracting
    }
    
    var formattedDaysOfWeek: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return daysOfWeek.map { dayNames[$0] }.joined(separator: ", ")
    }
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: averageDuration) ?? "0m"
    }
}

/// Represents a habit insight derived from detected patterns
struct HabitInsight: Identifiable {
    let id: String
    let title: String
    let description: String
    let type: InsightType
    let relatedHabits: [HabitPattern]
    let createdAt: Date
    
    enum InsightType: String, CaseIterable {
        case productivity
        case distraction
        case timeManagement
        case workLifeBalance
        case focus
        case suggestion
        
        var description: String {
            switch self {
            case .productivity: return "Productivity"
            case .distraction: return "Distraction"
            case .timeManagement: return "Time Management"
            case .workLifeBalance: return "Work-Life Balance"
            case .focus: return "Focus"
            case .suggestion: return "Suggestion"
            }
        }
        
        var iconName: String {
            switch self {
            case .productivity: return "chart.bar.fill"
            case .distraction: return "exclamationmark.triangle.fill"
            case .timeManagement: return "clock.fill"
            case .workLifeBalance: return "heart.fill"
            case .focus: return "eye.fill"
            case .suggestion: return "lightbulb.fill"
            }
        }
    }
}

/// Protocol for habit detection service
protocol HabitDetectionService {
    /// Analyzes activity data to detect habits
    func detectHabits() -> AnyPublisher<[HabitPattern], Error>
    
    /// Gets all detected habits
    func getAllHabits() -> AnyPublisher<[HabitPattern], Error>
    
    /// Gets habits by category
    func getHabits(category: ActivityCategory) -> AnyPublisher<[HabitPattern], Error>
    
    /// Gets habits by time of day
    func getHabits(timeOfDay: HabitPattern.TimeOfDay) -> AnyPublisher<[HabitPattern], Error>
    
    /// Gets habits for a specific day of week
    func getHabits(dayOfWeek: Int) -> AnyPublisher<[HabitPattern], Error>
    
    /// Gets habits for a specific application
    func getHabits(applicationName: String) -> AnyPublisher<[HabitPattern], Error>
    
    /// Generates insights based on detected habits
    func generateInsights() -> AnyPublisher<[HabitInsight], Error>
    
    /// Gets all generated insights
    func getAllInsights() -> AnyPublisher<[HabitInsight], Error>
    
    /// Gets the most recent insights (limited by count)
    func getRecentInsights(limit: Int) -> AnyPublisher<[HabitInsight], Error>
    
    /// Publisher for habit updates
    var habitsPublisher: AnyPublisher<[HabitPattern], Never> { get }
    
    /// Publisher for insight updates
    var insightsPublisher: AnyPublisher<[HabitInsight], Never> { get }
}

/// Implementation of the habit detection service
final class DefaultHabitDetectionService: HabitDetectionService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "HabitDetection")
    private let activityRepository: ActivityRecordRepositoryProtocol
    private let userDefaults: UserDefaults
    
    private var habits: [HabitPattern] = []
    private var insights: [HabitInsight] = []
    private var lastAnalysisDate: Date?
    
    private let habitsSubject = CurrentValueSubject<[HabitPattern], Never>([])
    private let insightsSubject = CurrentValueSubject<[HabitInsight], Never>([])
    
    private var cancellables = Set<AnyCancellable>()
    
    // Constants for habit detection
    private let minimumOccurrences = 3
    private let consistencyThreshold = 0.6
    private let analysisTimeWindow: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let lastAnalysisDate = "habitLastAnalysisDate"
        static let savedHabits = "savedHabits"
        static let savedInsights = "savedInsights"
    }
    
    // MARK: - Public Properties
    
    var habitsPublisher: AnyPublisher<[HabitPattern], Never> {
        return habitsSubject.eraseToAnyPublisher()
    }
    
    var insightsPublisher: AnyPublisher<[HabitInsight], Never> {
        return insightsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(activityRepository: ActivityRecordRepositoryProtocol, userDefaults: UserDefaults = .standard) {
        self.activityRepository = activityRepository
        self.userDefaults = userDefaults
        
        // Load saved data
        loadSavedData()
        
        // Setup periodic analysis
        setupPeriodicAnalysis()
        
        // Listen for new activities
        setupActivitySubscription()
    }
    
    // MARK: - Public Methods
    
    func detectHabits() -> AnyPublisher<[HabitPattern], Error> {
        return Future<[HabitPattern], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(HabitDetectionError.serviceUnavailable))
                return
            }
            
            self.performHabitAnalysis { result in
                switch result {
                case .success(let habits):
                    promise(.success(habits))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getAllHabits() -> AnyPublisher<[HabitPattern], Error> {
        return Just(habits)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getHabits(category: ActivityCategory) -> AnyPublisher<[HabitPattern], Error> {
        let filteredHabits = habits.filter { $0.category == category }
        return Just(filteredHabits)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getHabits(timeOfDay: HabitPattern.TimeOfDay) -> AnyPublisher<[HabitPattern], Error> {
        let filteredHabits = habits.filter { $0.timeOfDay == timeOfDay }
        return Just(filteredHabits)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getHabits(dayOfWeek: Int) -> AnyPublisher<[HabitPattern], Error> {
        let filteredHabits = habits.filter { $0.daysOfWeek.contains(dayOfWeek) }
        return Just(filteredHabits)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getHabits(applicationName: String) -> AnyPublisher<[HabitPattern], Error> {
        let filteredHabits = habits.filter { $0.applicationName == applicationName }
        return Just(filteredHabits)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func generateInsights() -> AnyPublisher<[HabitInsight], Error> {
        return Future<[HabitInsight], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(HabitDetectionError.serviceUnavailable))
                return
            }
            
            self.performInsightGeneration { result in
                switch result {
                case .success(let insights):
                    promise(.success(insights))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getAllInsights() -> AnyPublisher<[HabitInsight], Error> {
        return Just(insights)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getRecentInsights(limit: Int) -> AnyPublisher<[HabitInsight], Error> {
        let sortedInsights = insights.sorted { $0.createdAt > $1.createdAt }
        let limitedInsights = Array(sortedInsights.prefix(limit))
        
        return Just(limitedInsights)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func loadSavedData() {
        // Load habits
        if let habitsData = userDefaults.data(forKey: UserDefaultsKeys.savedHabits) {
            do {
                habits = try JSONDecoder().decode([HabitPattern].self, from: habitsData)
                habitsSubject.send(habits)
                logger.info("Loaded \(habits.count) saved habits")
            } catch {
                logger.error("Failed to decode saved habits: \(error.localizedDescription)")
            }
        }
        
        // Load insights
        if let insightsData = userDefaults.data(forKey: UserDefaultsKeys.savedInsights) {
            do {
                insights = try JSONDecoder().decode([HabitInsight].self, from: insightsData)
                insightsSubject.send(insights)
                logger.info("Loaded \(insights.count) saved insights")
            } catch {
                logger.error("Failed to decode saved insights: \(error.localizedDescription)")
            }
        }
        
        // Load last analysis date
        lastAnalysisDate = userDefaults.object(forKey: UserDefaultsKeys.lastAnalysisDate) as? Date
    }
    
    private func saveHabits() {
        do {
            let data = try JSONEncoder().encode(habits)
            userDefaults.set(data, forKey: UserDefaultsKeys.savedHabits)
            logger.info("Saved \(habits.count) habits")
        } catch {
            logger.error("Failed to encode habits: \(error.localizedDescription)")
        }
    }
    
    private func saveInsights() {
        do {
            let data = try JSONEncoder().encode(insights)
            userDefaults.set(data, forKey: UserDefaultsKeys.savedInsights)
            logger.info("Saved \(insights.count) insights")
        } catch {
            logger.error("Failed to encode insights: \(error.localizedDescription)")
        }
    }
    
    private func setupPeriodicAnalysis() {
        // Check if we need to run analysis on startup
        let now = Date()
        if let lastAnalysis = lastAnalysisDate {
            let daysSinceLastAnalysis = Calendar.current.dateComponents([.day], from: lastAnalysis, to: now).day ?? 0
            
            if daysSinceLastAnalysis >= 1 {
                // It's been at least a day since the last analysis, run it now
                performHabitAnalysis { _ in }
            }
        } else {
            // No previous analysis, run it now
            performHabitAnalysis { _ in }
        }
        
        // Schedule daily analysis
        Timer.publish(every: 24 * 60 * 60, on: .main, in: .common) // Daily
            .autoconnect()
            .sink { [weak self] _ in
                self?.performHabitAnalysis { _ in }
            }
            .store(in: &cancellables)
    }
    
    private func setupActivitySubscription() {
        activityRepository.activityPublisher
            .sink { _ in
                // We don't need to do anything on completion
            } receiveValue: { [weak self] _ in
                // New activity was added, but we don't need to analyze immediately
                // The periodic analysis will handle it
            }
            .store(in: &cancellables)
    }
    
    private func performHabitAnalysis(completion: @escaping (Result<[HabitPattern], Error>) -> Void) {
        logger.info("Starting habit analysis")
        
        // Get activities from the last 30 days
        let now = Date()
        let startDate = now.addingTimeInterval(-analysisTimeWindow)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(.failure(HabitDetectionError.serviceUnavailable))
                return
            }
            
            do {
                // Get all activities in the time window
                let activities = try self.activityRepository.getActivitiesInRange(from: startDate, to: now)
                
                // Group activities by application
                var applicationGroups: [String: [ActivityRecord]] = [:]
                
                for activity in activities {
                    let appName = activity.applicationName
                    if applicationGroups[appName] == nil {
                        applicationGroups[appName] = []
                    }
                    applicationGroups[appName]?.append(activity)
                }
                
                // Detect patterns in each application group
                var detectedPatterns: [HabitPattern] = []
                
                for (appName, appActivities) in applicationGroups {
                    // Skip if too few activities
                    if appActivities.count < self.minimumOccurrences {
                        continue
                    }
                    
                    // Group by time of day
                    var timeOfDayGroups: [HabitPattern.TimeOfDay: [ActivityRecord]] = [:]
                    
                    for activity in appActivities {
                        let hour = Calendar.current.component(.hour, from: activity.startTime)
                        let timeOfDay = HabitPattern.TimeOfDay.fromHour(hour)
                        
                        if timeOfDayGroups[timeOfDay] == nil {
                            timeOfDayGroups[timeOfDay] = []
                        }
                        timeOfDayGroups[timeOfDay]?.append(activity)
                    }
                    
                    // Analyze each time of day group
                    for (timeOfDay, timeActivities) in timeOfDayGroups {
                        // Skip if too few activities in this time slot
                        if timeActivities.count < self.minimumOccurrences {
                            continue
                        }
                        
                        // Group by day of week
                        var dayOfWeekCounts: [Int: Int] = [:]
                        var totalDuration: TimeInterval = 0
                        var categoryCount: [ActivityCategory: Int] = [:]
                        
                        for activity in timeActivities {
                            let dayOfWeek = Calendar.current.component(.weekday, from: activity.startTime) - 1 // 0-based
                            dayOfWeekCounts[dayOfWeek, default: 0] += 1
                            
                            if let duration = activity.durationInSeconds {
                                totalDuration += duration
                            }
                            
                            categoryCount[activity.category, default: 0] += 1
                        }
                        
                        // Determine the most common category
                        let dominantCategory = categoryCount.max { $0.value < $1.value }?.key ?? .neutral
                        
                        // Calculate average duration
                        let averageDuration = totalDuration / Double(timeActivities.count)
                        
                        // Determine which days of week this habit occurs on
                        let daysOfWeek = dayOfWeekCounts.filter { $0.value >= self.minimumOccurrences }.map { $0.key }
                        
                        // Skip if no consistent days
                        if daysOfWeek.isEmpty {
                            continue
                        }
                        
                        // Calculate consistency (how regularly this pattern occurs)
                        let totalPossibleOccurrences = daysOfWeek.count * (Int(self.analysisTimeWindow) / (24 * 60 * 60))
                        let consistency = Double(timeActivities.count) / Double(totalPossibleOccurrences)
                        
                        // Skip if consistency is too low
                        if consistency < self.consistencyThreshold {
                            continue
                        }
                        
                        // Create a habit pattern
                        let pattern = HabitPattern(
                            id: UUID().uuidString,
                            name: "\(appName) \(timeOfDay.description)",
                            description: "Regular use of \(appName) during \(timeOfDay.description)",
                            applicationName: appName,
                            category: dominantCategory,
                            timeOfDay: timeOfDay,
                            daysOfWeek: daysOfWeek,
                            averageDuration: averageDuration,
                            consistency: consistency,
                            firstDetected: timeActivities.map { $0.startTime }.min() ?? now,
                            lastObserved: timeActivities.map { $0.startTime }.max() ?? now,
                            occurrences: timeActivities.count
                        )
                        
                        detectedPatterns.append(pattern)
                    }
                }
                
                // Update habits list, keeping existing habits that are still valid
                var updatedHabits: [HabitPattern] = []
                
                // Keep existing habits that are still detected
                for existingHabit in self.habits {
                    if let matchingPattern = detectedPatterns.first(where: { $0.applicationName == existingHabit.applicationName && $0.timeOfDay == existingHabit.timeOfDay }) {
                        updatedHabits.append(matchingPattern)
                    } else {
                        // Check if this habit is still recent enough to keep
                        let daysSinceLastObserved = Calendar.current.dateComponents([.day], from: existingHabit.lastObserved, to: now).day ?? 0
                        
                        if daysSinceLastObserved <= 14 { // Keep habits observed in the last 2 weeks
                            updatedHabits.append(existingHabit)
                        }
                    }
                }
                
                // Add new habits that weren't in the existing list
                for newPattern in detectedPatterns {
                    if !updatedHabits.contains(where: { $0.applicationName == newPattern.applicationName && $0.timeOfDay == newPattern.timeOfDay }) {
                        updatedHabits.append(newPattern)
                    }
                }
                
                // Update the habits list
                self.habits = updatedHabits
                
                // Save to UserDefaults
                self.saveHabits()
                
                // Update last analysis date
                self.lastAnalysisDate = now
                self.userDefaults.set(now, forKey: UserDefaultsKeys.lastAnalysisDate)
                
                // Notify subscribers
                DispatchQueue.main.async {
                    self.habitsSubject.send(self.habits)
                    
                    // Generate insights based on the updated habits
                    self.performInsightGeneration { _ in }
                    
                    completion(.success(self.habits))
                }
                
            } catch {
                self.logger.error("Habit analysis failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    private func performInsightGeneration(completion: @escaping (Result<[HabitInsight], Error>) -> Void) {
        logger.info("Generating insights from habits")
        
        // Skip if no habits
        if habits.isEmpty {
            completion(.success([]))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(.failure(HabitDetectionError.serviceUnavailable))
                return
            }
            
            var newInsights: [HabitInsight] = []
            
            // Productive morning habit insight
            let morningProductiveHabits = self.habits.filter { 
                $0.isProductiveHabit && 
                ($0.timeOfDay == .earlyMorning || $0.timeOfDay == .morning) &&
                $0.consistency >= 0.7
            }
            
            if !morningProductiveHabits.isEmpty {
                let insight = HabitInsight(
                    id: UUID().uuidString,
                    title: "Productive Morning Routine",
                    description: "You have a consistent productive morning routine with \(morningProductiveHabits.count) regular activities.",
                    type: .productivity,
                    relatedHabits: morningProductiveHabits,
                    createdAt: Date()
                )
                newInsights.append(insight)
            }
            
            // Evening distraction insight
            let eveningDistractingHabits = self.habits.filter {
                $0.isDistractingHabit &&
                ($0.timeOfDay == .evening || $0.timeOfDay == .night) &&
                $0.consistency >= 0.6
            }
            
            if !eveningDistractingHabits.isEmpty {
                let insight = HabitInsight(
                    id: UUID().uuidString,
                    title: "Evening Distractions",
                    description: "You tend to engage with distracting content in the evenings, which might affect your wind-down routine.",
                    type: .distraction,
                    relatedHabits: eveningDistractingHabits,
                    createdAt: Date()
                )
                newInsights.append(insight)
            }
            
            // Work-life balance insight
            let workdayHabits = self.habits.filter {
                $0.daysOfWeek.contains(1) && // Monday
                $0.daysOfWeek.contains(2) && // Tuesday
                $0.daysOfWeek.contains(3) && // Wednesday
                $0.daysOfWeek.contains(4) && // Thursday
                $0.daysOfWeek.contains(5)    // Friday
            }
            
            let weekendHabits = self.habits.filter {
                $0.daysOfWeek.contains(0) || // Sunday
                $0.daysOfWeek.contains(6)    // Saturday
            }
            
            if !workdayHabits.isEmpty && !weekendHabits.isEmpty {
                // Check if there's good separation between work and weekend
                let workdayProductiveCount = workdayHabits.filter { $0.isProductiveHabit }.count
                let weekendDistractingCount = weekendHabits.filter { $0.isDistractingHabit }.count
                
                if workdayProductiveCount > 0 && weekendDistractingCount > 0 {
                    let insight = HabitInsight(
                        id: UUID().uuidString,
                        title: "Healthy Work-Life Balance",
                        description: "You maintain a good separation between productive workdays and relaxing weekends.",
                        type: .workLifeBalance,
                        relatedHabits: workdayHabits + weekendHabits,
                        createdAt: Date()
                    )
                    newInsights.append(insight)
                }
            }
            
            // Focus time insight
            let longFocusSessions = self.habits.filter {
                $0.isProductiveHabit &&
                $0.averageDuration >= 45 * 60 // 45 minutes or longer
            }
            
            if !longFocusSessions.isEmpty {
                let insight = HabitInsight(
                    id: UUID().uuidString,
                    title: "Strong Focus Sessions",
                    description: "You regularly engage in focused work sessions lasting 45+ minutes, which is excellent for deep work.",
                    type: .focus,
                    relatedHabits: longFocusSessions,
                    createdAt: Date()
                )
                newInsights.append(insight)
            }
            
            // Time management suggestion
            let shortDistractingSessions = self.habits.filter {
                $0.isDistractingHabit &&
                $0.averageDuration <= 5 * 60 && // 5 minutes or less
                $0.occurrences >= 10 // Happens frequently
            }
            
            if !shortDistractingSessions.isEmpty {
                let insight = HabitInsight(
                    id: UUID().uuidString,
                    title: "Frequent Short Distractions",
                    description: "You have frequent short distractions throughout the day. Consider batching these activities to reduce context switching.",
                    type: .suggestion,
                    relatedHabits: shortDistractingSessions,
                    createdAt: Date()
                )
                newInsights.append(insight)
            }
            
            // Update insights list, keeping recent insights
            var updatedInsights = self.insights.filter {
                // Keep insights from the last 30 days
                Calendar.current.dateComponents([.day], from: $0.createdAt, to: Date()).day ?? 0 <= 30
            }
            
            // Add new insights
            updatedInsights.append(contentsOf: newInsights)
            
            // Update the insights list
            self.insights = updatedInsights
            
            // Save to UserDefaults
            self.saveInsights()
            
            // Notify subscribers
            DispatchQueue.main.async {
                self.insightsSubject.send(self.insights)
                completion(.success(self.insights))
            }
        }
    }
}

enum HabitDetectionError: Error {
    case serviceUnavailable
    case insufficientData
    case analysisFailure
    
    var localizedDescription: String {
        switch self {
        case .serviceUnavailable:
            return "Habit detection service is not available"
        case .insufficientData:
            return "Not enough activity data to detect habits"
        case .analysisFailure:
            return "Failed to analyze activity data"
        }
    }
} 
 