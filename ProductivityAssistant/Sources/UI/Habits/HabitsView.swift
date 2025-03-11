import SwiftUI
import Combine

struct HabitsView: View {
    @StateObject private var viewModel = HabitsViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack {
                Button(action: { selectedTab = 0 }) {
                    Text("Habits")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(selectedTab == 0 ? Color.blue.opacity(0.1) : Color.clear)
                        .foregroundColor(selectedTab == 0 ? .blue : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { selectedTab = 1 }) {
                    Text("Insights")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(selectedTab == 1 ? Color.blue.opacity(0.1) : Color.clear)
                        .foregroundColor(selectedTab == 1 ? .blue : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: viewModel.refreshData) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .padding()
            
            if viewModel.isLoading {
                ProgressView("Analyzing your habits...")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedTab) {
                    // Habits tab
                    HabitsListView(habits: viewModel.habits)
                        .tag(0)
                    
                    // Insights tab
                    InsightsListView(insights: viewModel.insights)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .onAppear {
            viewModel.loadData()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct HabitsListView: View {
    let habits: [HabitPattern]
    @State private var selectedCategory: String = "all"
    @State private var selectedTimeOfDay: String = "all"
    
    var filteredHabits: [HabitPattern] {
        var result = habits
        
        if selectedCategory != "all" {
            if let category = ActivityCategory(rawValue: selectedCategory) {
                result = result.filter { $0.category == category }
            }
        }
        
        if selectedTimeOfDay != "all" {
            if let timeOfDay = HabitPattern.TimeOfDay(rawValue: selectedTimeOfDay) {
                result = result.filter { $0.timeOfDay == timeOfDay }
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag("all")
                    Text("Productive").tag(ActivityCategory.productive.rawValue)
                    Text("Neutral").tag(ActivityCategory.neutral.rawValue)
                    Text("Distracting").tag(ActivityCategory.distracting.rawValue)
                }
                .frame(width: 180)
                
                Picker("Time of Day", selection: $selectedTimeOfDay) {
                    Text("All Times").tag("all")
                    ForEach(HabitPattern.TimeOfDay.allCases, id: \.self) { timeOfDay in
                        Text(timeOfDay.description).tag(timeOfDay.rawValue)
                    }
                }
                .frame(width: 220)
                
                Spacer()
                
                Text("\(filteredHabits.count) habits found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            if filteredHabits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No habits detected yet")
                        .font(.title3)
                    
                    Text("Continue using your computer normally, and we'll detect your habits over time.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(filteredHabits, id: \.id) { habit in
                            HabitCard(habit: habit)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct HabitCard: View {
    let habit: HabitPattern
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
                
                Text(habit.name)
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(habit.consistency * 100))%")
                    .font(.caption)
                    .padding(4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Text(habit.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(habit.formattedDaysOfWeek)
                        .font(.caption2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(habit.formattedDuration)
                        .font(.caption2)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("First Seen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(habit.firstDetected))
                        .font(.caption2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Occurrences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(habit.occurrences)")
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var categoryColor: Color {
        switch habit.category {
        case .productive: return .green
        case .neutral: return .yellow
        case .distracting: return .red
        default: return .blue
        }
    }
    
    private var categoryIcon: String {
        switch habit.category {
        case .productive: return "checkmark.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .distracting: return "exclamationmark.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct InsightsListView: View {
    let insights: [HabitInsight]
    
    var body: some View {
        if insights.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("No insights available yet")
                    .font(.title3)
                
                Text("As we learn more about your habits, we'll provide personalized insights here.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(insights, id: \.id) { insight in
                        InsightCard(insight: insight)
                    }
                }
                .padding()
            }
        }
    }
}

struct InsightCard: View {
    let insight: HabitInsight
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.type.iconName)
                    .foregroundColor(typeColor)
                
                Text(insight.title)
                    .font(.headline)
                
                Spacer()
                
                Text(insight.type.description)
                    .font(.caption)
                    .padding(4)
                    .background(typeColor.opacity(0.1))
                    .foregroundColor(typeColor)
                    .cornerRadius(4)
            }
            
            Text(insight.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !insight.relatedHabits.isEmpty {
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Text("Related Habits (\(insight.relatedHabits.count))")
                            .font(.caption)
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    Divider()
                    
                    ForEach(insight.relatedHabits, id: \.id) { habit in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.secondary)
                            
                            Text(habit.name)
                                .font(.caption)
                            
                            Spacer()
                            
                            Text(habit.formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            HStack {
                Spacer()
                
                Text("Generated \(formatDate(insight.createdAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(typeColor.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var typeColor: Color {
        switch insight.type {
        case .productivity: return .green
        case .distraction: return .red
        case .timeManagement: return .blue
        case .workLifeBalance: return .purple
        case .focus: return .orange
        case .suggestion: return .yellow
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

class HabitsViewModel: ObservableObject {
    @Published var habits: [HabitPattern] = []
    @Published var insights: [HabitInsight] = []
    @Published var isLoading = false
    
    private var habitDetectionService: HabitDetectionService?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Get service from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            habitDetectionService = appDelegate.getHabitDetectionService()
            
            // Subscribe to updates
            setupSubscriptions()
        }
    }
    
    func loadData() {
        loadHabits()
        loadInsights()
    }
    
    func refreshData() {
        guard let habitDetectionService = habitDetectionService, !isLoading else { return }
        
        isLoading = true
        
        habitDetectionService.detectHabits()
            .flatMap { _ in
                habitDetectionService.generateInsights()
            }
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        print("Failed to refresh habits: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.loadData()
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadHabits() {
        guard let habitDetectionService = habitDetectionService else { return }
        
        habitDetectionService.getAllHabits()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to load habits: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] habits in
                    self?.habits = habits
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadInsights() {
        guard let habitDetectionService = habitDetectionService else { return }
        
        habitDetectionService.getAllInsights()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Failed to load insights: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] insights in
                    self?.insights = insights.sorted { $0.createdAt > $1.createdAt }
                }
            )
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        guard let habitDetectionService = habitDetectionService else { return }
        
        habitDetectionService.habitsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] habits in
                self?.habits = habits
            }
            .store(in: &cancellables)
        
        habitDetectionService.insightsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] insights in
                self?.insights = insights.sorted { $0.createdAt > $1.createdAt }
            }
            .store(in: &cancellables)
    }
}

struct HabitsView_Previews: PreviewProvider {
    static var previews: some View {
        HabitsView()
    }
} 
 