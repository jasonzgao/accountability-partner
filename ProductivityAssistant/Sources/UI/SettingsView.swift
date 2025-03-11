import SwiftUI
import Combine
import os

struct SettingsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            CategoryRulesView()
                .tabItem {
                    Label("Categories", systemImage: "tag")
                }
                .tag(1)
            
            IntegrationsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }
                .tag(2)
            
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(3)
            
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(4)
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(5)
        }
        .padding()
        .frame(width: 600, height: 500)
    }
}

struct GeneralSettingsView: View {
    @StateObject private var viewModel = GeneralSettingsViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Tracking")) {
                Toggle("Start at login", isOn: $viewModel.startAtLogin)
                
                Picker("Idle threshold", selection: $viewModel.idleThresholdMinutes) {
                    ForEach([3, 5, 10, 15, 30], id: \.self) { minutes in
                        Text("\(minutes) minutes")
                            .tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("Track browser tabs", isOn: $viewModel.trackBrowserTabs)
                
                Toggle("Show status in menu bar", isOn: $viewModel.showStatusInMenuBar)
            }
            
            Section(header: Text("Data Management")) {
                HStack {
                    Picker("Data retention", selection: $viewModel.dataRetentionDays) {
                        ForEach([7, 14, 30, 60, 90, 180, 365], id: \.self) { days in
                            Text("\(days) days")
                                .tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Spacer()
                    
                    Button("Clear All Data") {
                        viewModel.showingDeleteConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding()
        .alert("Confirm Data Deletion", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Data", role: .destructive) {
                viewModel.clearAllData()
            }
        } message: {
            Text("This will delete all tracked activities and settings. This action cannot be undone.")
        }
    }
}

class GeneralSettingsViewModel: ObservableObject {
    @Published var startAtLogin: Bool = false
    @Published var idleThresholdMinutes: Int = 5
    @Published var trackBrowserTabs: Bool = true
    @Published var showStatusInMenuBar: Bool = true
    @Published var dataRetentionDays: Int = 30
    @Published var showingDeleteConfirmation: Bool = false
    
    private var activityMonitor: ActivityMonitorService?
    private var activityRepository: ActivityRecordRepositoryProtocol?
    private var dataRetentionService: DataRetentionServiceProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            activityMonitor = appDelegate.getActivityMonitor()
            activityRepository = appDelegate.getActivityRepository()
            dataRetentionService = appDelegate.getDataRetentionService()
            
            loadSettings()
            
            // When settings change, save them
            $idleThresholdMinutes
                .sink { [weak self] minutes in
                    self?.activityMonitor?.idleThreshold = TimeInterval(minutes * 60)
                }
                .store(in: &cancellables)
                
            $dataRetentionDays
                .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
                .sink { [weak self] days in
                    self?.updateDataRetentionPolicy(days: days)
                }
                .store(in: &cancellables)
        }
    }
    
    private func loadSettings() {
        // Load idle threshold from the activity monitor
        if let idleThreshold = activityMonitor?.idleThreshold {
            idleThresholdMinutes = Int(idleThreshold / 60.0)
        }
        
        // Load data retention period from the service
        if let retentionDays = dataRetentionService?.retentionPeriodDays, retentionDays > 0 {
            dataRetentionDays = retentionDays
        }
        
        // Load other settings from UserDefaults
        let defaults = UserDefaults.standard
        startAtLogin = defaults.bool(forKey: "startAtLogin")
        trackBrowserTabs = defaults.bool(forKey: "trackBrowserTabs")
        showStatusInMenuBar = defaults.bool(forKey: "showStatusInMenuBar")
    }
    
    private func updateDataRetentionPolicy(days: Int) {
        guard days > 0 else { return }
        
        // Update the retention service
        dataRetentionService?.updateRetentionPeriod(days: days)
        
        // Save to UserDefaults for persistence
        UserDefaults.standard.set(days, forKey: "dataRetentionDays")
    }
    
    func clearAllData() {
        do {
            if let dataRetentionService = dataRetentionService {
                let count = try dataRetentionService.clearAllData()
                
                // Log the result
                let logger = Logger(subsystem: "com.productivityassistant", category: "Settings")
                logger.info("Cleared all data: \(count) records deleted")
            }
        } catch {
            // Handle error
            let logger = Logger(subsystem: "com.productivityassistant", category: "Settings")
            logger.error("Failed to clear data: \(error.localizedDescription)")
        }
    }
}

struct IntegrationsView: View {
    @StateObject private var viewModel = IntegrationsViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Integrations")
                .font(.title)
            
            IntegrationRow(
                title: "Things 3",
                description: "Connect to your task manager",
                isConnected: viewModel.isThingsConnected,
                connectAction: {
                    viewModel.toggleThingsConnection()
                }
            )
            
            if viewModel.isThingsConnected {
                ThingsSettingsView(viewModel: viewModel)
            }
            
            IntegrationRow(
                title: "Notion Calendar",
                description: "Sync with your calendar",
                isConnected: viewModel.isNotionConnected,
                connectAction: {
                    viewModel.toggleNotionConnection()
                }
            )
            
            if viewModel.isNotionConnected {
                NotionSettingsView(viewModel: viewModel)
            }
            
            Spacer()
        }
        .padding()
        .alert(isPresented: $viewModel.showingError) {
            Alert(
                title: Text("Connection Error"),
                message: Text(viewModel.errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $viewModel.showingNotionAuthSheet) {
            NotionAuthView(viewModel: viewModel)
        }
    }
}

struct ThingsSettingsView: View {
    @ObservedObject var viewModel: IntegrationsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Things 3 Settings")
                .font(.headline)
            
            if viewModel.isLoadingTasks {
                ProgressView("Loading tasks...")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Tasks: \(viewModel.todayTasksCount)")
                    Text("Status: \(viewModel.isThingsInstalled ? "Connected" : "Not Connected")")
                    
                    if !viewModel.todayTasks.isEmpty {
                        Text("Due Today:")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .padding(.top, 8)
                        
                        ForEach(viewModel.todayTasks.prefix(5)) { task in
                            HStack {
                                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.completed ? .green : .gray)
                                
                                Text(task.title)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if !task.completed {
                                    Button(action: {
                                        viewModel.completeTask(task)
                                    }) {
                                        Text("Complete")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        if viewModel.todayTasks.count > 5 {
                            Text("+ \(viewModel.todayTasks.count - 5) more tasks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button("Refresh Tasks") {
                viewModel.loadTodayTasks()
            }
            .disabled(viewModel.isLoadingTasks || !viewModel.isThingsConnected)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct NotionSettingsView: View {
    @ObservedObject var viewModel: IntegrationsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notion Calendar Settings")
                .font(.headline)
            
            if viewModel.isLoadingNotionData {
                ProgressView("Loading databases...")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status: \(viewModel.isNotionConnected ? "Connected" : "Not Connected")")
                    
                    if !viewModel.notionDatabases.isEmpty {
                        Text("Select Calendar Database:")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .padding(.top, 8)
                        
                        Picker("Calendar Database", selection: $viewModel.selectedDatabaseId) {
                            ForEach(viewModel.notionDatabases) { database in
                                Text(database.title).tag(database.id)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        if viewModel.hasActiveDatabase {
                            Text("Upcoming Events:")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .padding(.top, 8)
                            
                            if viewModel.isLoadingEvents {
                                ProgressView("Loading events...")
                                    .padding(.top, 4)
                            } else if viewModel.upcomingEvents.isEmpty {
                                Text("No upcoming events")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            } else {
                                ForEach(viewModel.upcomingEvents.prefix(3)) { event in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            
                                            Text(event.timeRangeString)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if let location = event.location, !location.isEmpty {
                                            Text(location)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                                if viewModel.upcomingEvents.count > 3 {
                                    Text("+ \(viewModel.upcomingEvents.count - 3) more events")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack {
                Button("Refresh") {
                    viewModel.refreshNotionData()
                }
                .disabled(viewModel.isLoadingNotionData || !viewModel.isNotionConnected)
                
                Spacer()
                
                Button("Disconnect") {
                    viewModel.disconnectNotion()
                }
                .disabled(!viewModel.isNotionConnected)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct NotionAuthView: View {
    @ObservedObject var viewModel: IntegrationsViewModel
    @State private var token: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to Notion")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("To connect to Notion, you need to create an integration token in your Notion account.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Link("Create a Notion Integration", destination: URL(string: "https://www.notion.so/my-integrations")!)
                .padding(.bottom)
            
            TextField("Paste your integration token here", text: $token)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Connect") {
                    viewModel.authenticateNotion(token: token)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty)
            }
            .padding()
            
            if viewModel.isAuthenticatingNotion {
                ProgressView("Authenticating...")
            }
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

struct IntegrationRow: View {
    let title: String
    let description: String
    let isConnected: Bool
    let connectAction: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(isConnected ? "Disconnect" : "Connect") {
                connectAction()
            }
            .buttonStyle(isConnected ? .bordered : .borderedProminent)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct NotificationsView: View {
    @State private var enableNotifications = true
    @State private var notifyOnDistraction = true
    @State private var notifyOnProductivity = true
    @State private var notifyOnIdle = true
    @State private var dailySummary = true
    @State private var weeklySummary = true
    
    var body: some View {
        Form {
            Section(header: Text("General")) {
                Toggle("Enable Notifications", isOn: $enableNotifications)
            }
            
            Section(header: Text("Activity Notifications")) {
                Toggle("Notify when distracted for too long", isOn: $notifyOnDistraction)
                    .disabled(!enableNotifications)
                
                Toggle("Celebrate productive streaks", isOn: $notifyOnProductivity)
                    .disabled(!enableNotifications)
                
                Toggle("Notify when returning from idle", isOn: $notifyOnIdle)
                    .disabled(!enableNotifications)
            }
            
            Section(header: Text("Summaries")) {
                Toggle("Daily summary", isOn: $dailySummary)
                    .disabled(!enableNotifications)
                
                Toggle("Weekly summary", isOn: $weeklySummary)
                    .disabled(!enableNotifications)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Productivity Assistant")
                .font(.title)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("A macOS productivity tracking and accountability application that monitors user behavior, integrates with existing productivity tools, and provides intelligent coaching to help users stay focused on their goals.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
            
            Button("View License") {
                // Open license
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

class IntegrationsViewModel: ObservableObject {
    // MARK: - Published Properties - Things 3
    
    @Published var isThingsConnected: Bool = false
    @Published var isThingsInstalled: Bool = false
    @Published var todayTasks: [ThingsTask] = []
    @Published var isLoadingTasks: Bool = false
    
    // MARK: - Published Properties - Notion
    
    @Published var isNotionConnected: Bool = false
    @Published var isAuthenticatingNotion: Bool = false
    @Published var showingNotionAuthSheet: Bool = false
    @Published var notionDatabases: [NotionDatabase] = []
    @Published var selectedDatabaseId: String = ""
    @Published var upcomingEvents: [NotionEvent] = []
    @Published var isLoadingNotionData: Bool = false
    @Published var isLoadingEvents: Bool = false
    
    // MARK: - Common Properties
    
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""
    
    // MARK: - Private Properties
    
    private var thingsService: ThingsIntegrationService?
    private var notionService: NotionCalendarService?
    private var cancellables = Set<AnyCancellable>()
    
    var hasActiveDatabase: Bool {
        return !selectedDatabaseId.isEmpty
    }
    
    var todayTasksCount: Int {
        return todayTasks.count
    }
    
    // MARK: - Initialization
    
    init() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            // Initialize Things 3 integration
            thingsService = appDelegate.getThingsIntegrationService()
            isThingsInstalled = thingsService?.isThingsInstalled ?? false
            
            // Load from UserDefaults if Things 3 was previously connected
            isThingsConnected = UserDefaults.standard.bool(forKey: "isThingsConnected")
            
            // Only load tasks if connected
            if isThingsConnected && isThingsInstalled {
                loadTodayTasks()
            }
            
            // Initialize Notion integration
            notionService = appDelegate.getNotionCalendarService()
            isNotionConnected = notionService?.isAuthenticated ?? false
            
            // Load Notion data if connected
            if isNotionConnected {
                refreshNotionData()
                
                // Set selected database if available
                if let databaseId = notionService?.activeDatabaseId {
                    selectedDatabaseId = databaseId
                    loadUpcomingEvents()
                }
            }
            
            // Listen for changes to selected database
            $selectedDatabaseId
                .dropFirst() // Skip initial value
                .sink { [weak self] databaseId in
                    self?.setActiveDatabase(id: databaseId)
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Things 3 Methods
    
    func toggleThingsConnection() {
        guard let thingsService = thingsService else { return }
        
        if !isThingsInstalled {
            showError("Things 3 is not installed. Please install Things 3 to use this integration.")
            return
        }
        
        if isThingsConnected {
            // Disconnect
            isThingsConnected = false
            UserDefaults.standard.set(false, forKey: "isThingsConnected")
            todayTasks = []
        } else {
            // Try to connect
            isLoadingTasks = true
            
            thingsService.fetchTasksDueToday()
                .receive(on: RunLoop.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        self?.isLoadingTasks = false
                        
                        if case .failure(let error) = completion {
                            self?.handleConnectionError(error)
                        } else {
                            self?.isThingsConnected = true
                            UserDefaults.standard.set(true, forKey: "isThingsConnected")
                        }
                    },
                    receiveValue: { [weak self] tasks in
                        self?.todayTasks = tasks
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    func loadTodayTasks() {
        guard let thingsService = thingsService, isThingsConnected else { return }
        
        isLoadingTasks = true
        
        thingsService.fetchTasksDueToday()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingTasks = false
                    
                    if case .failure(let error) = completion {
                        self?.handleConnectionError(error)
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
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleConnectionError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.loadTodayTasks()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Notion Methods
    
    func toggleNotionConnection() {
        if isNotionConnected {
            disconnectNotion()
        } else {
            showingNotionAuthSheet = true
        }
    }
    
    func authenticateNotion(token: String) {
        guard let notionService = notionService, !token.isEmpty else { return }
        
        isAuthenticatingNotion = true
        
        notionService.authenticate(token: token)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isAuthenticatingNotion = false
                    
                    if case .failure(let error) = completion {
                        self?.handleNotionError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.isNotionConnected = true
                        self?.refreshNotionData()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func disconnectNotion() {
        guard let notionService = notionService else { return }
        
        notionService.logout()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleNotionError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.isNotionConnected = false
                        self?.notionDatabases = []
                        self?.upcomingEvents = []
                        self?.selectedDatabaseId = ""
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshNotionData() {
        guard let notionService = notionService, isNotionConnected else { return }
        
        isLoadingNotionData = true
        
        notionService.listDatabases()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingNotionData = false
                    
                    if case .failure(let error) = completion {
                        self?.handleNotionError(error)
                    }
                },
                receiveValue: { [weak self] databases in
                    self?.notionDatabases = databases
                    
                    // If we have a selected database, load events
                    if let self = self, !self.selectedDatabaseId.isEmpty {
                        self.loadUpcomingEvents()
                    } else if let databaseId = notionService.activeDatabaseId, !databases.isEmpty {
                        // If we have an active database but no selection, set it
                        self?.selectedDatabaseId = databaseId
                        self?.loadUpcomingEvents()
                    } else if !databases.isEmpty {
                        // If we have databases but no selection, select the first one
                        self?.selectedDatabaseId = databases[0].id
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func setActiveDatabase(id: String) {
        guard let notionService = notionService, isNotionConnected, !id.isEmpty else { return }
        
        notionService.setActiveDatabase(id: id)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleNotionError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.loadUpcomingEvents()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func loadUpcomingEvents() {
        guard let notionService = notionService, isNotionConnected, !selectedDatabaseId.isEmpty else { return }
        
        isLoadingEvents = true
        
        notionService.fetchUpcomingEvents(limit: 10)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingEvents = false
                    
                    if case .failure(let error) = completion {
                        self?.handleNotionError(error)
                    }
                },
                receiveValue: { [weak self] events in
                    self?.upcomingEvents = events
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Error Handling
    
    private func handleConnectionError(_ error: Error) {
        var message = "Failed to connect to Things 3."
        
        if let thingsError = error as? ThingsIntegrationError {
            message = thingsError.localizedDescription
        } else {
            message = "Error: \(error.localizedDescription)"
        }
        
        showError(message)
    }
    
    private func handleNotionError(_ error: Error) {
        var message = "Failed to connect to Notion."
        
        if let notionError = error as? NotionIntegrationError {
            message = notionError.localizedDescription
        } else {
            message = "Error: \(error.localizedDescription)"
        }
        
        showError(message)
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
} 