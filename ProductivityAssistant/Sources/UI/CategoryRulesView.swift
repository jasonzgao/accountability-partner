import SwiftUI
import Combine

struct CategoryRulesView: View {
    @StateObject private var viewModel = CategoryRulesViewModel()
    @State private var showingAddSheet = false
    @State private var selectedRule: CategoryRule?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Categories")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // Rule list
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.rules.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No Categorization Rules")
                        .font(.headline)
                    
                    Text("Add rules to customize how activities are categorized")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Add Rule") {
                        showingAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(viewModel.rulesByApplication.sorted(by: { $0.key < $1.key }), id: \.key) { appName, rules in
                        Section(header: Text(appName)) {
                            ForEach(rules, id: \.id) { rule in
                                RuleRow(rule: rule, categoryName: viewModel.categoryName(for: rule.categoryId))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedRule = rule
                                    }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    viewModel.deleteRule(rules[index])
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadRules()
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryRuleEditView(mode: .add, onSave: { rule in
                viewModel.addRule(rule)
                showingAddSheet = false
            })
        }
        .sheet(item: $selectedRule) { rule in
            CategoryRuleEditView(
                mode: .edit(rule),
                onSave: { updatedRule in
                    viewModel.updateRule(updatedRule)
                    selectedRule = nil
                }
            )
        }
    }
}

struct RuleRow: View {
    let rule: CategoryRule
    let categoryName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(categoryName)
                    .font(.headline)
                    .foregroundColor(categoryColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let urlPattern = rule.urlPattern {
                LabeledContent("URL Pattern:", value: urlPattern)
            }
            
            if let windowTitlePattern = rule.windowTitlePattern {
                LabeledContent("Window Title Pattern:", value: windowTitlePattern)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var categoryColor: Color {
        switch categoryName.lowercased() {
        case "productive":
            return .green
        case "neutral":
            return .yellow
        case "distracting":
            return .red
        default:
            return .blue
        }
    }
}

struct LabeledContent: View {
    let label: String
    let value: String
    
    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

struct CategoryRuleEditView: View {
    enum Mode {
        case add
        case edit(CategoryRule)
    }
    
    @StateObject private var viewModel = CategoryRuleEditViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    let mode: Mode
    let onSave: (CategoryRule) -> Void
    
    init(mode: Mode, onSave: @escaping (CategoryRule) -> Void) {
        self.mode = mode
        self.onSave = onSave
        
        if case .edit(let rule) = mode {
            _viewModel = StateObject(wrappedValue: CategoryRuleEditViewModel(rule: rule))
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Application")) {
                    TextField("Application Name", text: $viewModel.applicationName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Patterns")) {
                    TextField("URL Pattern (optional)", text: $viewModel.urlPattern)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Window Title Pattern (optional)", text: $viewModel.windowTitlePattern)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Category")) {
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        ForEach(ActivityCategory.allCases.filter { $0 != .custom }, id: \.self) { category in
                            HStack {
                                Image(systemName: category.iconName)
                                    .foregroundColor(category.color)
                                Text(category.displayName)
                            }
                            .tag(category)
                        }
                    }
                }
                
                if viewModel.errorMessage != nil {
                    Section {
                        Text(viewModel.errorMessage!)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(mode == .add ? "Add Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.validate() {
                            onSave(viewModel.createRule())
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

class CategoryRulesViewModel: ObservableObject {
    @Published var rules: [CategoryRule] = []
    @Published var categories: [ActivityCategoryRecord] = []
    @Published var isLoading = false
    
    private var categorizationService: ActivityCategorizationService?
    private var categoryRepository: CategoryRepositoryProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            categoryRepository = appDelegate.getCategoryRepository()
            
            // Listen for category changes
            categoryRepository?.categoryChangesPublisher
                .sink { [weak self] _ in
                    self?.loadCategories()
                    self?.loadRules()
                }
                .store(in: &cancellables)
        }
    }
    
    var rulesByApplication: [String: [CategoryRule]] {
        let groupedRules = Dictionary(grouping: rules) { rule in
            return rule.applicationName ?? "Unknown"
        }
        return groupedRules
    }
    
    func loadRules() {
        isLoading = true
        
        DispatchQueue.global().async { [weak self] in
            do {
                if let repository = self?.categoryRepository {
                    let loadedRules = try repository.getAllCategoryRules()
                    
                    DispatchQueue.main.async {
                        self?.rules = loadedRules
                        self?.isLoading = false
                    }
                }
            } catch {
                print("Failed to load rules: \(error)")
                
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }
        
        loadCategories()
    }
    
    func loadCategories() {
        DispatchQueue.global().async { [weak self] in
            do {
                if let repository = self?.categoryRepository {
                    let loadedCategories = try repository.getAllCategories()
                    
                    DispatchQueue.main.async {
                        self?.categories = loadedCategories
                    }
                }
            } catch {
                print("Failed to load categories: \(error)")
            }
        }
    }
    
    func categoryName(for categoryId: String) -> String {
        if let category = categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Unknown"
    }
    
    func addRule(_ rule: CategoryRule) {
        do {
            try categoryRepository?.saveCategoryRule(rule)
            loadRules()
        } catch {
            print("Failed to add rule: \(error)")
        }
    }
    
    func updateRule(_ rule: CategoryRule) {
        do {
            try categoryRepository?.updateCategoryRule(rule)
            loadRules()
        } catch {
            print("Failed to update rule: \(error)")
        }
    }
    
    func deleteRule(_ rule: CategoryRule) {
        do {
            try categoryRepository?.deleteCategoryRule(id: rule.id)
            loadRules()
        } catch {
            print("Failed to delete rule: \(error)")
        }
    }
}

class CategoryRuleEditViewModel: ObservableObject {
    @Published var applicationName: String = ""
    @Published var urlPattern: String = ""
    @Published var windowTitlePattern: String = ""
    @Published var selectedCategory: ActivityCategory = .neutral
    @Published var errorMessage: String?
    @Published var isValid: Bool = false
    
    private var ruleId: String
    
    init(rule: CategoryRule? = nil) {
        if let rule = rule {
            applicationName = rule.applicationName ?? ""
            urlPattern = rule.urlPattern ?? ""
            windowTitlePattern = rule.windowTitlePattern ?? ""
            ruleId = rule.id
            
            // Determine the category from the rule's category ID
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
               let repository = appDelegate.getCategoryRepository() {
                do {
                    if let category = try repository.getCategoryById(id: rule.categoryId) {
                        selectedCategory = category.type.toActivityCategory
                    }
                } catch {
                    print("Failed to get category: \(error)")
                }
            }
        } else {
            ruleId = UUID().uuidString
        }
        
        validate()
    }
    
    func validate() -> Bool {
        // Application name is required
        if applicationName.isEmpty {
            errorMessage = "Application name is required"
            isValid = false
            return false
        }
        
        // At least one pattern should be provided
        if urlPattern.isEmpty && windowTitlePattern.isEmpty {
            errorMessage = "Either URL pattern or window title pattern is required"
            isValid = false
            return false
        }
        
        errorMessage = nil
        isValid = true
        return true
    }
    
    func createRule() -> CategoryRule {
        let categoryId = ActivityCategoryType.from(selectedCategory).rawValue
        
        return CategoryRule(
            id: ruleId,
            applicationName: applicationName,
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            windowTitlePattern: windowTitlePattern.isEmpty ? nil : windowTitlePattern,
            categoryId: categoryId
        )
    }
}

struct CategoryRulesView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryRulesView()
    }
} 