import SwiftUI
import Combine

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @State private var showingCreateSheet = false
    @State private var selectedGoal: Goal?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.filteredGoals) { goal in
                    GoalRow(goal: goal)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedGoal = goal
                        }
                }
                .onDelete { indexSet in
                    viewModel.deleteGoals(at: indexSet)
                }
            }
            .frame(width: 300)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("Filter", selection: $viewModel.selectedFilter) {
                            ForEach(GoalsViewModel.GoalFilter.allCases, id: \.self) { filter in
                                Text(filter.description).tag(filter)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
                    }
                }
                
                ToolbarItem {
                    Button(action: {
                        showingCreateSheet = true
                    }) {
                        Label("Add Goal", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Goals")
            
            // Detail view when a goal is selected
            if let goal = selectedGoal {
                GoalDetailView(goal: goal, onDelete: {
                    viewModel.deleteGoal(goal)
                    selectedGoal = nil
                })
            } else {
                Text("Select a goal to view details")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Goals")
        .sheet(isPresented: $showingCreateSheet) {
            GoalCreationView()
                .onDisappear {
                    viewModel.loadGoals()
                }
        }
        .sheet(item: $selectedGoal) { goal in
            GoalCreationView(editingGoal: goal)
                .onDisappear {
                    viewModel.loadGoals()
                }
        }
        .onAppear {
            viewModel.loadGoals()
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

struct GoalRow: View {
    let goal: Goal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: goal.type.iconName)
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading) {
                    Text(goal.title)
                        .font(.headline)
                    
                    Text(goal.frequency.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(Int(goal.currentProgress))/\(Int(goal.target)) \(goal.displayUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: goal.progressPercentage)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 80)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        if goal.isCompleted {
            return .green
        } else if goal.isExpired {
            return .red
        } else if !goal.isActive {
            return .gray
        } else {
            return .blue
        }
    }
}

struct GoalDetailView: View {
    let goal: Goal
    let onDelete: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section with basic info and actions
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.title)
                            .font(.title)
                            .bold()
                        
                        if let description = goal.description, !description.isEmpty {
                            Text(description)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        HStack {
                            if goal.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Completed")
                                    .foregroundColor(.green)
                            } else if goal.isExpired {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Expired")
                                    .foregroundColor(.red)
                            } else if !goal.isActive {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundColor(.gray)
                                Text("Inactive")
                                    .foregroundColor(.gray)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Active")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Text("\(goal.frequency.description) goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Tab selection
                HStack {
                    Button(action: { selectedTab = 0 }) {
                        Text("Progress")
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedTab == 0 ? Color.blue.opacity(0.1) : Color.clear)
                            .foregroundColor(selectedTab == 0 ? .blue : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { selectedTab = 1 }) {
                        Text("Details")
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedTab == 1 ? Color.blue.opacity(0.1) : Color.clear)
                            .foregroundColor(selectedTab == 1 ? .blue : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Menu {
                        Button("Edit", action: {
                            // Edit action handled by selection in GoalsView
                        })
                        
                        Button("Delete", action: {
                            showingDeleteConfirmation = true
                        })
                        .foregroundColor(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .padding()
            
            // Tab content
            TabView(selection: $selectedTab) {
                // Progress tab
                GoalProgressView(goalId: goal.id)
                    .tag(0)
                
                // Details tab
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Key metrics section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Key Metrics")
                                .font(.headline)
                            
                            HStack(spacing: 24) {
                                VStack(alignment: .leading) {
                                    Text("Progress")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Text("\(Int(goal.currentProgress))/\(Int(goal.target)) \(goal.displayUnit)")
                                            .font(.title2)
                                        
                                        Text("(\(Int(goal.progressPercentage * 100))%)")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Days Completed")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(goal.daysCompleted)")
                                        .font(.title2)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Current Streak")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(goal.streak) days")
                                        .font(.title2)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Goal details section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Goal Details")
                                .font(.headline)
                            
                            detailRow(title: "Type", value: goal.type.description)
                            
                            detailRow(title: "Created", value: formatDate(goal.startDate))
                            
                            if let endDate = goal.endDate {
                                detailRow(title: "Due Date", value: formatDate(endDate))
                            }
                            
                            if let reminderTime = goal.reminderTime {
                                detailRow(title: "Reminder", value: formatTime(reminderTime))
                            }
                            
                            if let categoryFilter = goal.categoryFilter {
                                detailRow(title: "Category", value: categoryFilter)
                            }
                            
                            if let applicationFilter = goal.applicationFilter {
                                detailRow(title: "Application", value: applicationFilter)
                            }
                            
                            if let urlFilter = goal.urlFilter {
                                detailRow(title: "URL", value: urlFilter)
                            }
                            
                            detailRow(title: "Last Updated", value: formatDate(goal.lastUpdated))
                        }
                    }
                    .padding()
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Confirm Deletion"),
                message: Text("Are you sure you want to delete this goal? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    onDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

class GoalsViewModel: ObservableObject {
    enum GoalFilter: String, CaseIterable {
        case all
        case active
        case completed
        case expired
        case archived
        
        var description: String {
            switch self {
            case .all: return "All Goals"
            case .active: return "Active Goals"
            case .completed: return "Completed Goals"
            case .expired: return "Expired Goals"
            case .archived: return "Archived Goals"
            }
        }
    }
    
    @Published var allGoals: [Goal] = []
    @Published var filteredGoals: [Goal] = []
    @Published var selectedFilter: GoalFilter = .active {
        didSet {
            applyFilter()
        }
    }
    
    private var goalTrackingService: GoalTrackingService?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Get service from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            goalTrackingService = appDelegate.getGoalTrackingService()
            
            // Subscribe to goals updates
            setupSubscriptions()
        }
    }
    
    func loadGoals() {
        guard let goalTrackingService = goalTrackingService else { return }
        
        // Load all goals
        goalTrackingService.getGoals(matching: GoalFilter())
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to load goals: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] goals in
                    self?.allGoals = goals
                    self?.applyFilter()
                }
            )
            .store(in: &cancellables)
    }
    
    func deleteGoals(at indexSet: IndexSet) {
        guard let goalTrackingService = goalTrackingService else { return }
        
        for index in indexSet {
            let goal = filteredGoals[index]
            
            goalTrackingService.deleteGoal(id: goal.id)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("Failed to delete goal: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
    }
    
    func deleteGoal(_ goal: Goal) {
        guard let goalTrackingService = goalTrackingService else { return }
        
        goalTrackingService.deleteGoal(id: goal.id)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to delete goal: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        guard let goalTrackingService = goalTrackingService else { return }
        
        goalTrackingService.goalsPublisher
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Goals subscription error: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] goals in
                    self?.allGoals = goals
                    self?.applyFilter()
                }
            )
            .store(in: &cancellables)
    }
    
    private func applyFilter() {
        switch selectedFilter {
        case .all:
            filteredGoals = allGoals
        case .active:
            filteredGoals = allGoals.filter { $0.isActive && !$0.isCompleted && !$0.isArchived && !$0.isExpired }
        case .completed:
            filteredGoals = allGoals.filter { $0.isCompleted && !$0.isArchived }
        case .expired:
            filteredGoals = allGoals.filter { $0.isExpired && !$0.isArchived }
        case .archived:
            filteredGoals = allGoals.filter { $0.isArchived }
        }
    }
}

struct GoalsView_Previews: PreviewProvider {
    static var previews: some View {
        GoalsView()
    }
} 
 