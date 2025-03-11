import SwiftUI
import Charts

struct GoalProgressView: View {
    @StateObject private var viewModel: GoalProgressViewModel
    
    init(goalId: String) {
        _viewModel = StateObject(wrappedValue: GoalProgressViewModel(goalId: goalId))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Goal Summary Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Summary")
                        .font(.headline)
                    
                    if let goal = viewModel.goal {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title)
                                    .font(.title3)
                                    .bold()
                                
                                Text(goal.type.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            CircularProgressView(progress: goal.progressPercentage)
                                .frame(width: 60, height: 60)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        ProgressView()
                            .padding()
                    }
                }
                
                // Progress History Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progress History")
                        .font(.headline)
                    
                    if viewModel.isLoadingHistory {
                        ProgressView()
                            .padding()
                    } else if viewModel.progressHistory.isEmpty {
                        Text("No progress data available yet")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        // Line Chart showing progress over time
                        Chart(viewModel.progressHistory, id: \.date) { item in
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Progress", item.percentage * 100)
                            )
                            .foregroundStyle(Color.blue)
                            
                            PointMark(
                                x: .value("Date", item.date),
                                y: .value("Progress", item.percentage * 100)
                            )
                            .foregroundStyle(Color.blue)
                        }
                        .chartYAxis {
                            AxisMarks(preset: .extended, position: .leading) {
                                AxisValueLabel {
                                    Text("\($0.as(Double.self) ?? 0, format: .number)%")
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) {
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                        .frame(height: 200)
                        .padding()
                    }
                }
                
                // Daily Breakdown Section
                if !viewModel.dailyProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Breakdown")
                            .font(.headline)
                        
                        // Bar Chart showing daily progress
                        Chart(viewModel.dailyProgress, id: \.date) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Progress", item.value)
                            )
                            .foregroundStyle(Color.blue.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 7)) {
                                AxisValueLabel(format: .dateTime.weekday())
                            }
                        }
                        .frame(height: 200)
                        .padding()
                    }
                }
                
                // Related Activities Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Activities")
                        .font(.headline)
                    
                    if viewModel.isLoadingActivities {
                        ProgressView()
                            .padding()
                    } else if viewModel.relatedActivities.isEmpty {
                        Text("No related activities found")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.relatedActivities.prefix(5), id: \.id) { activity in
                            HStack {
                                Image(systemName: activity.applicationType.iconName)
                                    .foregroundColor(activity.category.color)
                                
                                VStack(alignment: .leading) {
                                    Text(activity.applicationName)
                                        .font(.system(size: 14, weight: .medium))
                                    
                                    if let windowTitle = activity.windowTitle {
                                        Text(windowTitle)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Text(viewModel.formatDuration(activity.durationInSeconds ?? 0))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Actions Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.headline)
                    
                    HStack {
                        Button(action: viewModel.loadData) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Spacer()
                        
                        Button(action: viewModel.recalculateProgress) {
                            Label("Recalculate Progress", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.loadData()
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 8.0)
                .opacity(0.3)
                .foregroundColor(Color.blue)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 8.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(Color.blue)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            Text(String(format: "%.0f%%", min(progress, 1.0) * 100.0))
                .font(.system(size: 14, weight: .bold))
        }
    }
}

class GoalProgressViewModel: ObservableObject {
    @Published var goal: Goal?
    @Published var progressHistory: [ProgressHistoryItem] = []
    @Published var dailyProgress: [DailyProgressItem] = []
    @Published var relatedActivities: [ActivityRecord] = []
    
    @Published var isLoadingGoal = false
    @Published var isLoadingHistory = false
    @Published var isLoadingActivities = false
    
    private let goalId: String
    private var goalTrackingService: GoalTrackingService?
    private var activityRepository: ActivityRecordRepositoryProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    struct ProgressHistoryItem {
        let date: Date
        let value: Double
        let target: Double
        let percentage: Double
        let isCompleted: Bool
    }
    
    struct DailyProgressItem {
        let date: Date
        let value: Double
    }
    
    init(goalId: String) {
        self.goalId = goalId
        
        // Get services
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            goalTrackingService = appDelegate.getGoalTrackingService()
            activityRepository = appDelegate.getActivityRepository()
        }
    }
    
    func loadData() {
        loadGoalDetails()
        loadProgressHistory()
        loadRelatedActivities()
    }
    
    func recalculateProgress() {
        guard let goalTrackingService = goalTrackingService else { return }
        
        goalTrackingService.calculateProgressForAllGoals()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to recalculate progress: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.loadData()
                }
            )
            .store(in: &cancellables)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "0m"
    }
    
    private func loadGoalDetails() {
        guard let goalTrackingService = goalTrackingService else { return }
        
        isLoadingGoal = true
        
        goalTrackingService.getGoal(id: goalId)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingGoal = false
                    
                    if case .failure(let error) = completion {
                        print("Failed to load goal: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] goal in
                    guard let self = self, let goal = goal else { return }
                    self.goal = goal
                    self.createDailyProgressData(for: goal)
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadProgressHistory() {
        guard let goalTrackingService = goalTrackingService else { return }
        
        isLoadingHistory = true
        
        goalTrackingService.getProgressHistory(goalId: goalId)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingHistory = false
                    
                    if case .failure(let error) = completion {
                        print("Failed to load progress history: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] records in
                    guard let self = self, let goal = self.goal else { return }
                    
                    // Convert records to history items
                    self.progressHistory = records.map { record in
                        ProgressHistoryItem(
                            date: record.date,
                            value: record.progressValue,
                            target: goal.target,
                            percentage: min(record.progressValue / goal.target, 1.0),
                            isCompleted: record.isCompleted
                        )
                    }
                    .sorted { $0.date < $1.date }
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadRelatedActivities() {
        guard let activityRepository = activityRepository, let goal = goal else { return }
        
        isLoadingActivities = true
        
        // Get activities from the last 7 days that match the goal's filters
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            do {
                var activities = try activityRepository.getActivitiesInRange(from: startDate, to: now)
                
                // Apply filters based on goal
                if let categoryFilter = goal.categoryFilter {
                    activities = activities.filter { $0.category.rawValue == categoryFilter }
                }
                
                if let appFilter = goal.applicationFilter, !appFilter.isEmpty {
                    activities = activities.filter { $0.applicationName.contains(appFilter) }
                }
                
                if let urlFilter = goal.urlFilter, !urlFilter.isEmpty {
                    activities = activities.filter { 
                        if let url = $0.url?.absoluteString {
                            return url.contains(urlFilter)
                        }
                        return false
                    }
                }
                
                // Sort by duration (longest first)
                activities.sort { 
                    ($0.durationInSeconds ?? 0) > ($1.durationInSeconds ?? 0)
                }
                
                DispatchQueue.main.async {
                    self?.relatedActivities = activities
                    self?.isLoadingActivities = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoadingActivities = false
                    print("Failed to load related activities: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createDailyProgressData(for goal: Goal) {
        // Create daily progress data based on the goal type and frequency
        let calendar = Calendar.current
        var startDate: Date
        
        // Determine the start date based on goal frequency
        switch goal.frequency {
        case .daily, .weekdays, .weekends, .custom:
            // For daily goals, show progress for the last 7 days
            startDate = calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        case .weekly:
            // For weekly goals, show progress for the last 4 weeks
            startDate = calendar.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date()
        case .monthly:
            // For monthly goals, show progress for the last 6 months
            startDate = calendar.date(byAdding: .month, value: -5, to: Date()) ?? Date()
        }
        
        // Start with an empty array
        dailyProgress = []
        
        // For now, generate some sample data
        // In a real implementation, this would be pulled from the history
        let now = Date()
        var currentDate = calendar.startOfDay(for: startDate)
        
        while currentDate <= now {
            // Find if there is a progress record for this day
            if let record = progressHistory.first(where: { 
                calendar.isDate($0.date, inSameDayAs: currentDate)
            }) {
                dailyProgress.append(DailyProgressItem(
                    date: currentDate,
                    value: record.value
                ))
            } else {
                // If no record, add a zero value
                dailyProgress.append(DailyProgressItem(
                    date: currentDate,
                    value: 0
                ))
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
    }
}

struct GoalProgressView_Previews: PreviewProvider {
    static var previews: some View {
        GoalProgressView(goalId: "preview-goal-id")
    }
} 
 