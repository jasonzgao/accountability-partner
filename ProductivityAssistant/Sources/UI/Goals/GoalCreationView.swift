import SwiftUI
import Combine

struct GoalCreationView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = GoalCreationViewModel()
    
    var editingGoal: Goal?
    
    init(editingGoal: Goal? = nil) {
        self.editingGoal = editingGoal
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Goal Details")) {
                    TextField("Title", text: $viewModel.title)
                    
                    TextField("Description", text: $viewModel.description)
                    
                    Picker("Type", selection: $viewModel.selectedType) {
                        ForEach(GoalType.allCases, id: \.self) { type in
                            Text(type.description).tag(type)
                        }
                    }
                    .onChange(of: viewModel.selectedType) { newValue in
                        viewModel.updateUnitForType(newValue)
                    }
                    
                    HStack {
                        TextField("Target", text: $viewModel.targetString)
                            .keyboardType(.decimalPad)
                        
                        Text(viewModel.unitLabel)
                    }
                    
                    if viewModel.selectedType == .custom {
                        TextField("Unit", text: $viewModel.customUnit)
                    }
                }
                
                Section(header: Text("Schedule")) {
                    Picker("Frequency", selection: $viewModel.selectedFrequency) {
                        ForEach(GoalFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.description).tag(frequency)
                        }
                    }
                    
                    if viewModel.selectedFrequency == .custom {
                        VStack(alignment: .leading) {
                            Text("Select Days:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                ForEach(0..<7) { index in
                                    let day = (index + 1) % 7  // 0 = Sunday, 1 = Monday, etc.
                                    
                                    Button(action: {
                                        viewModel.toggleCustomDay(day)
                                    }) {
                                        Text(viewModel.dayShortName(for: day))
                                            .padding(8)
                                            .background(
                                                viewModel.customDays.contains(day)
                                                    ? Color.blue
                                                    : Color.gray.opacity(0.2)
                                            )
                                            .foregroundColor(
                                                viewModel.customDays.contains(day)
                                                    ? .white
                                                    : .primary
                                            )
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                    
                    Toggle("Has End Date", isOn: $viewModel.hasEndDate)
                    
                    if viewModel.hasEndDate {
                        DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
                    }
                    
                    Picker("Reminder Time", selection: $viewModel.reminderSelection) {
                        Text("None").tag(-1)
                        ForEach(0..<24) { hour in
                            Text(viewModel.formatHour(hour)).tag(hour)
                        }
                    }
                }
                
                Section(header: Text("Filters")) {
                    Picker("Activity Category", selection: $viewModel.selectedCategoryId) {
                        Text("Any Category").tag("")
                        ForEach(viewModel.availableCategories, id: \.id) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    
                    TextField("Application (optional)", text: $viewModel.applicationFilter)
                    
                    TextField("Website URL (optional)", text: $viewModel.urlFilter)
                }
                
                Section {
                    Button(action: viewModel.saveGoal) {
                        Text(editingGoal == nil ? "Create Goal" : "Update Goal")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.isFormValid)
                    
                    if viewModel.showingError {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(editingGoal == nil ? "Create Goal" : "Edit Goal")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: editingGoal != nil ? Button("Delete") {
                    viewModel.showingDeleteConfirmation = true
                }
                .foregroundColor(.red) : nil
            )
            .alert(isPresented: $viewModel.showingDeleteConfirmation) {
                Alert(
                    title: Text("Confirm Deletion"),
                    message: Text("Are you sure you want to delete this goal? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        viewModel.deleteGoal()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                if let goal = editingGoal {
                    viewModel.initializeWithGoal(goal)
                }
            }
            .onChange(of: viewModel.shouldDismiss) { dismiss in
                if dismiss {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

class GoalCreationViewModel: ObservableObject {
    // Form fields
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var selectedType: GoalType = .timeSpent
    @Published var targetString: String = "1.0"
    @Published var customUnit: String = ""
    @Published var selectedFrequency: GoalFrequency = .daily
    @Published var customDays: [Int] = []
    @Published var startDate: Date = Date()
    @Published var hasEndDate: Bool = false
    @Published var endDate: Date = Date().addingTimeInterval(30 * 86400) // 30 days
    @Published var reminderSelection: Int = -1
    @Published var selectedCategoryId: String = ""
    @Published var applicationFilter: String = ""
    @Published var urlFilter: String = ""
    
    // View state
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""
    @Published var shouldDismiss: Bool = false
    @Published var showingDeleteConfirmation: Bool = false
    @Published var availableCategories: [ActivityCategoryRecord] = []
    
    private var goalToEdit: Goal?
    private var goalTrackingService: GoalTrackingService?
    private var categoryRepository: CategoryRepositoryProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Get services from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            goalTrackingService = appDelegate.getGoalTrackingService()
            categoryRepository = appDelegate.getCategoryRepository()
            
            // Load categories
            loadCategories()
        }
    }
    
    var isFormValid: Bool {
        // Basic validation
        guard !title.isEmpty else { return false }
        guard let _ = Double(targetString) else { return false }
        
        // Custom unit validation
        if selectedType == .custom && customUnit.isEmpty {
            return false
        }
        
        // End date validation
        if hasEndDate && endDate <= startDate {
            return false
        }
        
        // Custom day validation
        if selectedFrequency == .custom && customDays.isEmpty {
            return false
        }
        
        return true
    }
    
    var unitLabel: String {
        switch selectedType {
        case .timeSpent, .timeLimit:
            return "hours"
        case .activityCount:
            return "instances"
        case .activityRatio:
            return "%"
        case .completion:
            return "tasks"
        case .custom:
            return customUnit
        }
    }
    
    func dayShortName(for day: Int) -> String {
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        return days[day]
    }
    
    func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(hour):00"
    }
    
    func updateUnitForType(_ type: GoalType) {
        if type != .custom {
            customUnit = unitLabel
        }
    }
    
    func toggleCustomDay(_ day: Int) {
        if let index = customDays.firstIndex(of: day) {
            customDays.remove(at: index)
        } else {
            customDays.append(day)
        }
    }
    
    func initializeWithGoal(_ goal: Goal) {
        self.goalToEdit = goal
        
        title = goal.title
        description = goal.description ?? ""
        selectedType = goal.type
        targetString = String(format: "%.1f", goal.target)
        customUnit = goal.unit
        selectedFrequency = goal.frequency
        
        if let customDays = goal.customFrequencyDays {
            self.customDays = customDays
        }
        
        startDate = goal.startDate
        
        if let endDate = goal.endDate {
            hasEndDate = true
            self.endDate = endDate
        } else {
            hasEndDate = false
        }
        
        if let reminderTime = goal.reminderTime {
            let hour = Calendar.current.component(.hour, from: reminderTime)
            reminderSelection = hour
        } else {
            reminderSelection = -1
        }
        
        selectedCategoryId = goal.categoryFilter ?? ""
        applicationFilter = goal.applicationFilter ?? ""
        urlFilter = goal.urlFilter ?? ""
    }
    
    func saveGoal() {
        guard isFormValid else {
            showError("Please check the form for errors.")
            return
        }
        
        guard let goalTrackingService = goalTrackingService else {
            showError("Service unavailable. Please try again later.")
            return
        }
        
        // Prepare goal data
        let targetValue = Double(targetString) ?? 0
        
        var reminderTime: Date?
        if reminderSelection >= 0 {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = reminderSelection
            components.minute = 0
            components.second = 0
            reminderTime = calendar.date(from: components)
        }
        
        let newGoal = Goal(
            id: goalToEdit?.id ?? UUID().uuidString,
            title: title,
            description: description.isEmpty ? nil : description,
            type: selectedType,
            frequency: selectedFrequency,
            target: targetValue,
            currentProgress: goalToEdit?.currentProgress ?? 0.0,
            unit: selectedType == .custom ? customUnit : unitLabel,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            categoryFilter: selectedCategoryId.isEmpty ? nil : selectedCategoryId,
            applicationFilter: applicationFilter.isEmpty ? nil : applicationFilter,
            urlFilter: urlFilter.isEmpty ? nil : urlFilter,
            lastUpdated: Date(),
            isActive: true,
            daysCompleted: goalToEdit?.daysCompleted ?? 0,
            streak: goalToEdit?.streak ?? 0,
            customFrequencyDays: selectedFrequency == .custom ? customDays : nil,
            reminderTime: reminderTime,
            isArchived: false
        )
        
        let publisher = goalToEdit == nil
            ? goalTrackingService.createGoal(newGoal)
            : goalTrackingService.updateGoal(newGoal)
            
        publisher
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.showError("Failed to save goal: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.shouldDismiss = true
                }
            )
            .store(in: &cancellables)
    }
    
    func deleteGoal() {
        guard let goalId = goalToEdit?.id, let goalTrackingService = goalTrackingService else {
            return
        }
        
        goalTrackingService.deleteGoal(id: goalId)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.showError("Failed to delete goal: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.shouldDismiss = true
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadCategories() {
        guard let categoryRepository = categoryRepository else { return }
        
        do {
            availableCategories = try categoryRepository.getAllCategories()
        } catch {
            print("Error loading categories: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

struct GoalCreationView_Previews: PreviewProvider {
    static var previews: some View {
        GoalCreationView()
    }
} 
 