import SwiftUI
import Combine

struct MenuBarView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel = MenuBarViewModel()
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 16) {
            // Status header
            HStack {
                statusIcon
                    .font(.system(size: 24))
                Text(viewModel.currentStatus.description)
                    .font(.headline)
                Spacer()
                
                if viewModel.isUserIdle {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.gray)
                        Text("Idle")
                            .foregroundColor(.gray)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                }
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Today's progress
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today's Progress")
                        .font(.headline)
                    Spacer()
                    Button(action: { viewModel.openStatistics() }) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption)
                        Text("Statistics")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(spacing: 8) {
                    progressRow(
                        label: "Productive:",
                        time: viewModel.productiveTime,
                        percentage: viewModel.productivePercentage,
                        color: .green
                    )
                    
                    progressRow(
                        label: "Neutral:",
                        time: viewModel.neutralTime,
                        percentage: viewModel.neutralPercentage,
                        color: .yellow
                    )
                    
                    progressRow(
                        label: "Distractions:",
                        time: viewModel.distractingTime,
                        percentage: viewModel.distractingPercentage,
                        color: .red
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Today's Tasks (Things 3)
            if viewModel.isThingsConnected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's Tasks")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: { viewModel.refreshThingsTasks() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoadingTasks)
                    }
                    
                    if viewModel.isLoadingTasks {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.top, 4)
                    } else if viewModel.todayTasks.isEmpty {
                        Text("No tasks due today")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.todayTasks.prefix(5)) { task in
                                    HStack(alignment: .top) {
                                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(task.completed ? .green : .gray)
                                            .font(.system(size: 14))
                                            .frame(width: 20)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            
                                            if let project = task.project, !project.isEmpty {
                                                Text(project)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if !task.completed {
                                            Button(action: {
                                                viewModel.completeTask(task)
                                            }) {
                                                Text("Done")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                
                                if viewModel.todayTasks.count > 5 {
                                    Text("+ \(viewModel.todayTasks.count - 5) more tasks")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(height: min(CGFloat(viewModel.todayTasks.count) * 25 + 20, 150))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            // Upcoming Events (Notion)
            if viewModel.isNotionConnected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Upcoming Events")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: { viewModel.refreshNotionEvents() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoadingEvents)
                    }
                    
                    if viewModel.isLoadingEvents {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.top, 4)
                    } else if viewModel.upcomingEvents.isEmpty {
                        Text("No upcoming events")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.upcomingEvents.prefix(3)) { event in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 9))
                                                
                                                Text(event.timeRangeString)
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(.secondary)
                                            
                                            if let location = event.location, !location.isEmpty {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "mappin")
                                                        .font(.system(size: 9))
                                                    
                                                    Text(location)
                                                        .font(.system(size: 10))
                                                }
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                
                                if viewModel.upcomingEvents.count > 3 {
                                    Text("+ \(viewModel.upcomingEvents.count - 3) more events")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(height: min(CGFloat(viewModel.upcomingEvents.count) * 40 + 20, 150))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            // Current application
            if let currentApp = viewModel.currentApplication {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Activity")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Image(systemName: currentApp.applicationType.iconName)
                            .foregroundColor(currentApp.category.color)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentApp.applicationName)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            
                            if let windowTitle = currentApp.windowTitle {
                                Text(windowTitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            if let url = currentApp.url {
                                Text(url.host ?? url.absoluteString)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            // Quick actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions")
                    .font(.headline)
                
                HStack(spacing: 8) {
                    actionButton(
                        title: "Focus Mode",
                        icon: "timer",
                        action: { viewModel.startFocusSession() }
                    )
                    
                    actionButton(
                        title: "Re-categorize",
                        icon: "tag",
                        action: { viewModel.showCategoryPicker() }
                    )
                    
                    actionButton(
                        title: "Goals",
                        icon: "target",
                        action: { viewModel.openGoals() }
                    )
                    
                    actionButton(
                        title: "Habits",
                        icon: "calendar.badge.clock",
                        action: { viewModel.openHabits() }
                    )
                    
                    actionButton(
                        title: "Notifications",
                        icon: "bell",
                        action: { viewModel.openNotifications() }
                    )
                    
                    actionButton(
                        title: "Settings",
                        icon: "gear",
                        action: { viewModel.openSettings() }
                    )
                }
            }
            
            Spacer()
            
            // Application version
            Text("Productivity Assistant v1.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            viewModel.loadData()
        }
        .sheet(isPresented: $viewModel.showingCategorySheet) {
            if let app = viewModel.currentApplication {
                CategoryPickerView(activity: app)
            }
        }
    }
    
    // MARK: - Components
    
    private var statusIcon: some View {
        switch viewModel.currentStatus {
        case .productive:
            return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .neutral:
            return Image(systemName: "minus.circle.fill").foregroundColor(.yellow)
        case .distracted:
            return Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
        }
    }
    
    private func progressRow(label: String, time: String, percentage: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(time)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: geometry.size.width, height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: max(geometry.size.width * percentage, 3), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

struct CategoryPickerView: View {
    let activity: ActivityRecord
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = CategoryPickerViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Categorize Activity")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Application: \(activity.applicationName)")
                if let windowTitle = activity.windowTitle {
                    Text("Window: \(windowTitle)")
                }
                if let url = activity.url {
                    Text("URL: \(url.absoluteString)")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            
            Divider()
            
            Text("Select Category:")
                .font(.subheadline)
            
            ForEach(ActivityCategory.allCases, id: \.self) { category in
                Button(action: {
                    viewModel.categorizeActivity(activity, as: category)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: category.iconName)
                            .foregroundColor(category.color)
                        Text(category.displayName)
                        Spacer()
                        if activity.category == category {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 350, height: 400)
    }
}

class MenuBarViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentStatus: ActivityStatus = .neutral
    @Published var isUserIdle: Bool = false
    @Published var currentApplication: ActivityRecord?
    @Published var productiveTime: String = "0h 0m"
    @Published var neutralTime: String = "0h 0m"
    @Published var distractingTime: String = "0h 0m"
    @Published var productivePercentage: Double = 0.0
    @Published var neutralPercentage: Double = 0.0
    @Published var distractingPercentage: Double = 0.0
    @Published var showingCategorySheet: Bool = false
    
    // Things 3 integration
    @Published var isThingsConnected: Bool = false
    @Published var todayTasks: [ThingsTask] = []
    @Published var isLoadingTasks: Bool = false
    
    // Notion integration
    @Published var isNotionConnected: Bool = false
    @Published var upcomingEvents: [NotionEvent] = []
    @Published var isLoadingEvents: Bool = false
    
    // MARK: - Private Properties
    
    private var activityMonitor: ActivityMonitorService?
    private var activityRepository: ActivityRecordRepositoryProtocol?
    private var thingsService: ThingsIntegrationService?
    private var notionService: NotionCalendarService?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // We'll get references to our services via the app delegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            activityMonitor = appDelegate.getActivityMonitor()
            activityRepository = appDelegate.getActivityRepository()
            thingsService = appDelegate.getThingsIntegrationService()
            notionService = appDelegate.getNotionCalendarService()
            
            // Check if Things is connected
            isThingsConnected = UserDefaults.standard.bool(forKey: "isThingsConnected") &&
                                (thingsService?.isThingsInstalled ?? false)
            
            // Check if Notion is connected
            isNotionConnected = notionService?.isAuthenticated ?? false
            
            setupSubscriptions()
        }
    }
    
    // MARK: - Public Methods
    
    func loadData() {
        updateCurrentActivity()
        calculateDailyStats()
        
        // Load Things tasks if connected
        if isThingsConnected {
            refreshThingsTasks()
        }
        
        // Load Notion events if connected
        if isNotionConnected {
            refreshNotionEvents()
        }
    }
    
    func startFocusSession() {
        // To be implemented
    }
    
    func showCategoryPicker() {
        showingCategorySheet = true
    }
    
    func openSettings() {
        // Open the settings window using the AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.openSettings()
        }
    }
    
    func openStatistics() {
        // Open the statistics window using the AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.openStatistics()
        }
    }
    
    func openGoals() {
        // Open the goals window using the AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.openGoals()
        }
    }
    
    func openHabits() {
        // Open the habits window using the AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.openHabits()
        }
    }
    
    func openNotifications() {
        // Open the notifications window using the AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.openNotifications()
        }
    }
    
    func refreshThingsTasks() {
        guard let thingsService = thingsService, isThingsConnected else { return }
        
        isLoadingTasks = true
        
        thingsService.fetchTasksDueToday()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingTasks = false
                    
                    if case .failure(let error) = completion {
                        print("Error loading tasks: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] tasks in
                    self?.todayTasks = tasks
                }
            )
            .store(in: &cancellables)
    }
    
    func completeTask(_ task: ThingsTask) {
        guard let thingsService = thingsService else { return }
        
        thingsService.markTaskComplete(id: task.id)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Error completing task: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.refreshThingsTasks()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshNotionEvents() {
        guard let notionService = notionService, isNotionConnected, notionService.activeDatabaseId != nil else { return }
        
        isLoadingEvents = true
        
        notionService.fetchUpcomingEvents(limit: 5)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingEvents = false
                    
                    if case .failure(let error) = completion {
                        print("Error loading events: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] events in
                    self?.upcomingEvents = events
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Listen for activity updates
        activityMonitor?.startMonitoring()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] activity in
                    self?.currentApplication = activity
                    self?.updateStatus(from: activity)
                }
            )
            .store(in: &cancellables)
        
        // Listen for idle state changes
        activityMonitor?.idleStatePublisher
            .sink { [weak self] isIdle in
                self?.isUserIdle = isIdle
            }
            .store(in: &cancellables)
        
        // Refresh stats periodically
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.calculateDailyStats()
            }
            .store(in: &cancellables)
    }
    
    private func updateCurrentActivity() {
        currentApplication = activityMonitor?.getCurrentActivity()
        
        if let activity = currentApplication {
            updateStatus(from: activity)
        }
    }
    
    private func updateStatus(from activity: ActivityRecord) {
        switch activity.category {
        case .productive:
            currentStatus = .productive
        case .neutral:
            currentStatus = .neutral
        case .distracting:
            currentStatus = .distracted
        case .custom:
            // For custom categories, would need more sophisticated logic
            currentStatus = .neutral
        }
    }
    
    private func calculateDailyStats() {
        guard let repository = activityRepository else { return }
        
        do {
            let today = Date()
            let activities = try repository.getActivitiesInRange(from: today.startOfDay, to: today.endOfDay)
            
            var productiveSeconds: TimeInterval = 0
            var neutralSeconds: TimeInterval = 0
            var distractingSeconds: TimeInterval = 0
            
            for activity in activities {
                guard let duration = activity.durationInSeconds else { continue }
                
                switch activity.category {
                case .productive:
                    productiveSeconds += duration
                case .neutral:
                    neutralSeconds += duration
                case .distracting:
                    distractingSeconds += duration
                case .custom:
                    // Would need more logic for custom categories
                    neutralSeconds += duration
                }
            }
            
            // Update time strings
            productiveTime = Date.formatTimeInterval(productiveSeconds)
            neutralTime = Date.formatTimeInterval(neutralSeconds)
            distractingTime = Date.formatTimeInterval(distractingSeconds)
            
            // Calculate percentages
            let totalSeconds = productiveSeconds + neutralSeconds + distractingSeconds
            if totalSeconds > 0 {
                productivePercentage = productiveSeconds / totalSeconds
                neutralPercentage = neutralSeconds / totalSeconds
                distractingPercentage = distractingSeconds / totalSeconds
            }
        } catch {
            print("Error calculating daily stats: \(error)")
        }
    }
}

class CategoryPickerViewModel: ObservableObject {
    private var activityMonitor: ActivityMonitorService?
    
    init() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            activityMonitor = appDelegate.getActivityMonitor()
        }
    }
    
    func categorizeActivity(_ activity: ActivityRecord, as category: ActivityCategory) {
        activityMonitor?.categorizeActivity(activity, as: category)
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
    }
} 