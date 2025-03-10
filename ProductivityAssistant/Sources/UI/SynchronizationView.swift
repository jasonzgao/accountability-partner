import SwiftUI
import Combine

class SynchronizationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var lastSyncResult: SyncResult?
    @Published var isRunning: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncedServices: [String] = []
    @Published var failedServices: [String] = []
    
    // MARK: - Private Properties
    
    private let synchronizationService: SynchronizationService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(synchronizationService: SynchronizationService) {
        self.synchronizationService = synchronizationService
        
        // Initialize with current state
        self.isRunning = synchronizationService.isRunning
        self.isSyncing = synchronizationService.isSyncing
        self.lastSyncTime = synchronizationService.lastSyncTime
        self.lastSyncResult = synchronizationService.lastSyncResult
        
        if let result = lastSyncResult {
            self.syncedServices = result.syncedServices
            self.failedServices = Array(result.errors.keys)
        }
        
        // Subscribe to sync status updates
        synchronizationService.syncStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.syncStatus = status
                self?.updateState(with: status)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func syncNow() {
        synchronizationService.syncNow()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] result in
                    self?.lastSyncResult = result
                    self?.lastSyncTime = result.endTime
                    self?.syncedServices = result.syncedServices
                    self?.failedServices = Array(result.errors.keys)
                }
            )
            .store(in: &cancellables)
    }
    
    func startSyncService() {
        synchronizationService.start()
        isRunning = true
    }
    
    func stopSyncService() {
        synchronizationService.stop()
        isRunning = false
    }
    
    // MARK: - Helper Methods
    
    private func updateState(with status: SyncStatus) {
        switch status {
        case .idle:
            isSyncing = false
        case .syncing(let progress, let service):
            isSyncing = true
        case .error(let message):
            isSyncing = false
        case .success(let result):
            isSyncing = false
            lastSyncResult = result
            lastSyncTime = result.endTime
            syncedServices = result.syncedServices
            failedServices = Array(result.errors.keys)
        }
    }
    
    // MARK: - Formatted Values
    
    var formattedLastSyncTime: String {
        guard let lastSyncTime = lastSyncTime else {
            return "Never"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSyncTime, relativeTo: Date())
    }
    
    var syncStatusText: String {
        switch syncStatus {
        case .idle:
            return "Idle"
        case .syncing(let progress, let service):
            return "Syncing \(service) (\(Int(progress * 100))%)"
        case .error(let message):
            return "Error: \(message)"
        case .success:
            return "Sync completed"
        }
    }
    
    var syncStatusColor: Color {
        switch syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .error:
            return .red
        case .success:
            return .green
        }
    }
    
    var syncDuration: String? {
        guard let result = lastSyncResult else {
            return nil
        }
        
        return String(format: "%.1f seconds", result.duration)
    }
}

struct SynchronizationView: View {
    @StateObject var viewModel: SynchronizationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            
            Divider()
            
            statusSection
            
            Divider()
            
            servicesSection
            
            Spacer()
            
            controlsSection
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Synchronization")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Manage data synchronization with external services")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.syncNow()
            }) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(viewModel.isSyncing)
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(viewModel.syncStatusColor)
                    .frame(width: 10, height: 10)
                
                Text(viewModel.syncStatusText)
                    .foregroundColor(viewModel.syncStatusColor)
            }
            
            HStack {
                Text("Last sync:")
                Text(viewModel.formattedLastSyncTime)
                    .foregroundColor(.secondary)
            }
            
            if let duration = viewModel.syncDuration {
                HStack {
                    Text("Duration:")
                    Text(duration)
                        .foregroundColor(.secondary)
                }
            }
            
            if viewModel.isSyncing {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Services")
                .font(.headline)
            
            if viewModel.syncedServices.isEmpty && viewModel.failedServices.isEmpty {
                Text("No services have been synchronized yet")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(viewModel.syncedServices, id: \.self) { service in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            
                            Text(service)
                        }
                    }
                    
                    ForEach(viewModel.failedServices, id: \.self) { service in
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            
                            Text(service)
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var controlsSection: some View {
        HStack {
            Spacer()
            
            Toggle("Automatic Synchronization", isOn: Binding(
                get: { self.viewModel.isRunning },
                set: { newValue in
                    if newValue {
                        self.viewModel.startSyncService()
                    } else {
                        self.viewModel.stopSyncService()
                    }
                }
            ))
            .toggleStyle(SwitchToggleStyle())
        }
    }
}

#Preview {
    // Create a mock synchronization service for preview
    let mockService = MockSynchronizationService()
    return SynchronizationView(viewModel: SynchronizationViewModel(synchronizationService: mockService))
}

// MARK: - Mock for Preview

class MockSynchronizationService: SynchronizationService {
    var isSyncing: Bool = false
    var isRunning: Bool = true
    var lastSyncTime: Date? = Date().addingTimeInterval(-3600) // 1 hour ago
    var lastSyncResult: SyncResult? = SyncResult(
        startTime: Date().addingTimeInterval(-3605),
        endTime: Date().addingTimeInterval(-3600),
        success: true,
        syncedServices: ["Things", "Notion"],
        errors: [:]
    )
    
    var syncStatusSubject = CurrentValueSubject<SyncStatus, Never>(.idle)
    
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> {
        return syncStatusSubject.eraseToAnyPublisher()
    }
    
    func start() {
        isRunning = true
    }
    
    func stop() {
        isRunning = false
    }
    
    func syncNow() -> AnyPublisher<SyncResult, Error> {
        isSyncing = true
        syncStatusSubject.send(.syncing(progress: 0.0, service: "Preparing"))
        
        // Simulate sync process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncStatusSubject.send(.syncing(progress: 0.3, service: "Things"))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.syncStatusSubject.send(.syncing(progress: 0.6, service: "Notion"))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isSyncing = false
            let result = SyncResult(
                startTime: Date().addingTimeInterval(-5),
                endTime: Date(),
                success: true,
                syncedServices: ["Things", "Notion"],
                errors: [:]
            )
            self.lastSyncResult = result
            self.lastSyncTime = result.endTime
            self.syncStatusSubject.send(.success(result: result))
        }
        
        return Just(SyncResult(
            startTime: Date().addingTimeInterval(-5),
            endTime: Date(),
            success: true,
            syncedServices: ["Things", "Notion"],
            errors: [:]
        ))
        .setFailureType(to: Error.self)
        .eraseToAnyPublisher()
    }
} 