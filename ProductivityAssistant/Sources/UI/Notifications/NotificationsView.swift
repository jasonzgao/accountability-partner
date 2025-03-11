import SwiftUI
import Combine

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var selectedType: String = "all"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with filter and actions
            HStack {
                Picker("Filter", selection: $selectedType) {
                    Text("All").tag("all")
                    ForEach(NotificationType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
                .frame(width: 200)
                .onChange(of: selectedType) { newValue in
                    viewModel.filterNotifications(by: newValue)
                }
                
                Spacer()
                
                Button(action: viewModel.markAllAsRead) {
                    Text("Mark All as Read")
                }
                .disabled(viewModel.filteredNotifications.isEmpty || viewModel.filteredNotifications.allSatisfy { $0.isRead })
                
                Button(action: viewModel.clearAllNotifications) {
                    Text("Clear All")
                }
                .disabled(viewModel.filteredNotifications.isEmpty)
            }
            .padding()
            
            Divider()
            
            if viewModel.isLoading {
                ProgressView("Loading notifications...")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredNotifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No notifications")
                        .font(.title3)
                    
                    Text("You don't have any notifications at the moment.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredNotifications) { notification in
                            NotificationRow(
                                notification: notification,
                                onMarkAsRead: { viewModel.markAsRead(id: notification.id) },
                                onDelete: { viewModel.deleteNotification(id: notification.id) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            viewModel.loadNotifications()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    let onMarkAsRead: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: notification.type.iconName)
                .font(.title2)
                .foregroundColor(typeColor)
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(formatDate(notification.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(notification.body)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                if let url = notification.actionURL {
                    Link(destination: url) {
                        Text("Open")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
            }
            
            // Actions
            if isHovering {
                HStack(spacing: 8) {
                    if !notification.isRead {
                        Button(action: onMarkAsRead) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(notification.isRead ? Color.clear : Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var typeColor: Color {
        switch notification.type {
        case .productivityAlert: return .green
        case .distractionAlert: return .red
        case .goalReminder: return .blue
        case .goalAchieved: return .purple
        case .dailySummary, .weeklySummary: return .orange
        case .habitInsight: return .yellow
        case .focusTime: return .blue
        case .idleReturn: return .gray
        case .systemAlert: return .secondary
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

class NotificationsViewModel: ObservableObject {
    @Published var allNotifications: [AppNotification] = []
    @Published var filteredNotifications: [AppNotification] = []
    @Published var isLoading = false
    
    private var notificationService: NotificationService?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Get service from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            notificationService = appDelegate.getNotificationService()
            
            // Subscribe to updates
            setupSubscriptions()
        }
    }
    
    func loadNotifications() {
        guard let notificationService = notificationService else { return }
        
        isLoading = true
        
        notificationService.getAllNotifications()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        print("Failed to load notifications: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] notifications in
                    self?.allNotifications = notifications
                    self?.filteredNotifications = notifications
                }
            )
            .store(in: &cancellables)
    }
    
    func filterNotifications(by typeString: String) {
        if typeString == "all" {
            filteredNotifications = allNotifications
        } else if let type = NotificationType(rawValue: typeString) {
            filteredNotifications = allNotifications.filter { $0.type == type }
        }
    }
    
    func markAsRead(id: String) {
        guard let notificationService = notificationService else { return }
        
        notificationService.markAsRead(id: id)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to mark notification as read: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    func markAllAsRead() {
        guard let notificationService = notificationService else { return }
        
        notificationService.markAllAsRead()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to mark all notifications as read: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    func deleteNotification(id: String) {
        guard let notificationService = notificationService else { return }
        
        notificationService.deleteNotification(id: id)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to delete notification: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    func clearAllNotifications() {
        guard let notificationService = notificationService else { return }
        
        notificationService.deleteAllNotifications()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to clear all notifications: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        guard let notificationService = notificationService else { return }
        
        notificationService.notificationsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] notifications in
                self?.allNotifications = notifications
                
                // Reapply current filter
                if let selectedType = self?.filteredNotifications.first?.type {
                    self?.filteredNotifications = notifications.filter { $0.type == selectedType }
                } else {
                    self?.filteredNotifications = notifications
                }
            }
            .store(in: &cancellables)
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView()
    }
} 
 