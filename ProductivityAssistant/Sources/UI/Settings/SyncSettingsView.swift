import SwiftUI
import Combine

struct SyncSettingsView: View {
    @StateObject private var viewModel = SyncSettingsViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Synchronization Status")) {
                HStack {
                    Text("Status:")
                    Spacer()
                    HStack {
                        statusIndicator
                        Text(viewModel.syncStatusDescription)
                    }
                }
                
                HStack {
                    Text("Last Sync:")
                    Spacer()
                    Text(viewModel.lastSyncTimeFormatted)
                }
                
                HStack {
                    Text("Auto Sync:")
                    Spacer()
                    Toggle("", isOn: $viewModel.autoSyncEnabled)
                        .labelsHidden()
                        .onChange(of: viewModel.autoSyncEnabled) { newValue in
                            viewModel.toggleAutoSync(enabled: newValue)
                        }
                }
                
                Button(action: viewModel.syncNow) {
                    HStack {
                        Text("Sync Now")
                        
                        if viewModel.isSyncing {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(viewModel.isSyncing)
            }
            
            Section(header: Text("Sync Settings")) {
                Picker("Sync Interval", selection: $viewModel.syncIntervalMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                    Text("6 hours").tag(360)
                    Text("12 hours").tag(720)
                    Text("24 hours").tag(1440)
                }
                .onChange(of: viewModel.syncIntervalMinutes) { newValue in
                    viewModel.updateSyncInterval(minutes: newValue)
                }
                
                Toggle("Sync on App Launch", isOn: $viewModel.syncOnLaunch)
                    .onChange(of: viewModel.syncOnLaunch) { newValue in
                        viewModel.updateSyncOnLaunch(enabled: newValue)
                    }
                
                Toggle("Sync on Network Change", isOn: $viewModel.syncOnNetworkChange)
                    .onChange(of: viewModel.syncOnNetworkChange) { newValue in
                        viewModel.updateSyncOnNetworkChange(enabled: newValue)
                    }
            }
            
            Section(header: Text("Services")) {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(viewModel.isThingsConnected ? .green : .gray)
                        Text("Things 3")
                        Spacer()
                        Text(viewModel.isThingsConnected ? "Connected" : "Not Connected")
                            .foregroundColor(viewModel.isThingsConnected ? .secondary : .red)
                    }
                    
                    if !viewModel.isThingsConnected {
                        Text("Install Things 3 to enable syncing tasks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(viewModel.isNotionConnected ? .green : .gray)
                        Text("Notion Calendar")
                        Spacer()
                        Text(viewModel.isNotionConnected ? "Connected" : "Not Connected")
                            .foregroundColor(viewModel.isNotionConnected ? .secondary : .red)
                    }
                    
                    if !viewModel.isNotionConnected {
                        Button("Connect to Notion") {
                            viewModel.showNotionSettings()
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let lastResult = viewModel.lastSyncResult {
                Section(header: Text("Last Sync Result")) {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(lastResult.successful ? "Success" : "Failed")
                            .foregroundColor(lastResult.successful ? .green : .red)
                    }
                    
                    if !lastResult.successful, let errorMessage = lastResult.errorMessage {
                        HStack {
                            Text("Error:")
                            Spacer()
                            Text(errorMessage)
                                .foregroundColor(.red)
                        }
                    }
                    
                    if lastResult.successful {
                        HStack {
                            Text("Items Synced:")
                            Spacer()
                            Text("\(lastResult.itemsSynced)")
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            viewModel.loadSettings()
        }
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }
    
    private var statusColor: Color {
        switch viewModel.syncStatus {
        case .idle:
            return .green
        case .syncing:
            return .blue
        case .error:
            return .red
        case .offline:
            return .orange
        }
    }
}

class SyncSettingsViewModel: ObservableObject {
    // Published properties
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncStatusDescription: String = "Idle"
    @Published var lastSyncTimeFormatted: String = "Never"
    @Published var autoSyncEnabled: Bool = true
    @Published var syncIntervalMinutes: Int = 30
    @Published var syncOnLaunch: Bool = true
    @Published var syncOnNetworkChange: Bool = true
    @Published var isSyncing: Bool = false
    @Published var isThingsConnected: Bool = false
    @Published var isNotionConnected: Bool = false
    @Published var lastSyncResult: SyncResult?
    
    // Private properties
    private var synchronizationService: SynchronizationService?
    private var thingsService: ThingsIntegrationService?
    private var notionService: NotionCalendarService?
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let syncIntervalMinutes = "syncIntervalMinutes"
        static let syncOnLaunch = "syncOnLaunch"
        static let syncOnNetworkChange = "syncOnNetworkChange"
        static let autoSyncEnabled = "autoSyncEnabled"
    }
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Get services from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            synchronizationService = appDelegate.getSynchronizationService()
            thingsService = appDelegate.getThingsIntegrationService()
            notionService = appDelegate.getNotionCalendarService()
        }
        
        setupSubscriptions()
    }
    
    func loadSettings() {
        // Load settings from UserDefaults
        autoSyncEnabled = userDefaults.bool(forKey: UserDefaultsKeys.autoSyncEnabled)
        syncIntervalMinutes = userDefaults.integer(forKey: UserDefaultsKeys.syncIntervalMinutes)
        if syncIntervalMinutes == 0 {
            syncIntervalMinutes = 30 // Default value
        }
        
        syncOnLaunch = userDefaults.bool(forKey: UserDefaultsKeys.syncOnLaunch)
        if !userDefaults.contains(key: UserDefaultsKeys.syncOnLaunch) {
            syncOnLaunch = true // Default value
        }
        
        syncOnNetworkChange = userDefaults.bool(forKey: UserDefaultsKeys.syncOnNetworkChange)
        if !userDefaults.contains(key: UserDefaultsKeys.syncOnNetworkChange) {
            syncOnNetworkChange = true // Default value
        }
        
        // Check service connections
        isThingsConnected = thingsService?.isThingsInstalled ?? false
        isNotionConnected = notionService?.isAuthenticated ?? false
        
        // Update current status
        if let service = synchronizationService {
            syncStatus = service.syncStatus
            syncStatusDescription = service.syncStatus.description
            isSyncing = service.syncStatus == .syncing
            
            if let lastSyncTime = service.lastSyncTime {
                updateLastSyncTimeFormatted(lastSyncTime)
            }
            
            lastSyncResult = service.lastSyncResult
        }
    }
    
    func syncNow() {
        guard let service = synchronizationService, !isSyncing else { return }
        
        service.syncNow()
            .sink { _ in }
            .store(in: &cancellables)
    }
    
    func toggleAutoSync(enabled: Bool) {
        guard let service = synchronizationService else { return }
        
        userDefaults.set(enabled, forKey: UserDefaultsKeys.autoSyncEnabled)
        
        if enabled {
            service.startService()
        } else {
            service.stopService()
        }
    }
    
    func updateSyncInterval(minutes: Int) {
        userDefaults.set(minutes, forKey: UserDefaultsKeys.syncIntervalMinutes)
        
        // To apply the new interval, restart the service if it's running
        if let service = synchronizationService, service.isRunning {
            service.stopService()
            service.startService()
        }
    }
    
    func updateSyncOnLaunch(enabled: Bool) {
        userDefaults.set(enabled, forKey: UserDefaultsKeys.syncOnLaunch)
    }
    
    func updateSyncOnNetworkChange(enabled: Bool) {
        userDefaults.set(enabled, forKey: UserDefaultsKeys.syncOnNetworkChange)
    }
    
    func showNotionSettings() {
        // Opens the Notion section of the settings
        // This would typically be handled by a coordinator or navigation controller
        // For now, we'll just print a message
        print("Navigate to Notion settings")
    }
    
    private func setupSubscriptions() {
        guard let service = synchronizationService else { return }
        
        // Subscribe to status changes
        service.syncStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.syncStatus = status
                self?.syncStatusDescription = status.description
                self?.isSyncing = status == .syncing
            }
            .store(in: &cancellables)
        
        // Subscribe to result updates
        service.syncResultPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                self?.lastSyncResult = result
                
                if let timestamp = self?.lastSyncResult?.timestamp {
                    self?.updateLastSyncTimeFormatted(timestamp)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateLastSyncTimeFormatted(_ date: Date) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        
        lastSyncTimeFormatted = formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

struct SyncSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SyncSettingsView()
    }
} 
 