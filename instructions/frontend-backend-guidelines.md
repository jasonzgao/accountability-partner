# Frontend & Backend Guidelines

## 1. Frontend Development Guidelines

### UI/UX Principles
- Follow macOS Human Interface Guidelines
- Minimal, non-distracting interface
- Consistent visual hierarchy
- Progressive disclosure of complex features
- Accessibility compliance (VoiceOver support, keyboard navigation)

### Component Structure
- Use MVVM (Model-View-ViewModel) architecture
- Create reusable components for common elements
- Maintain clear separation between data and presentation
- Use SwiftUI previews for rapid iteration

### State Management
- Use Combine publishers for reactive state updates
- Create a centralized AppState object for global state
- Use environment objects for dependency injection
- Implement proper state isolation to prevent cascading updates

### Code Style
```swift
// Prefer structs over classes when possible
struct ProductivityView: View {
    // MARK: - Properties
    
    @ObservedObject var viewModel: ProductivityViewModel
    @State private var isExpanded = false
    
    // MARK: - View
    
    var body: some View {
        VStack(spacing: 12) {
            headerView
            if isExpanded {
                detailsView
            }
            actionButtons
        }
        .padding()
        .onAppear {
            viewModel.loadData()
        }
    }
    
    // MARK: - Private Views
    
    private var headerView: some View {
        // Component implementation
    }
    
    private var detailsView: some View {
        // Component implementation
    }
    
    private var actionButtons: some View {
        // Component implementation
    }
    
    // MARK: - Private Methods
    
    private func handleAction() {
        // Method implementation
    }
}
```

### Performance Considerations
- Avoid expensive operations on the main thread
- Use lazy loading for off-screen content
- Implement proper view recycling for lists
- Cache images and computed values
- Profile UI rendering regularly

### Testing Strategy
- Write unit tests for all ViewModels
- Create snapshot tests for UI components
- Implement UI automation tests for critical flows
- Test across multiple macOS versions (Ventura, Sonoma)

## 2. Backend Development Guidelines

### Architecture Principles
- Use Clean Architecture approach
- Create well-defined boundaries between layers
- Implement dependency inversion for testability
- Prefer protocol-based interfaces

### Service Layer Design
```swift
// Protocol defines the interface
protocol ActivityMonitorService {
    func startMonitoring() -> AnyPublisher<ActivityRecord, Error>
    func getCurrentActivity() -> ActivityRecord?
}

// Concrete implementation
final class MacOSActivityMonitor: ActivityMonitorService {
    // MARK: - Dependencies
    
    private let accessibilityService: AccessibilityService
    private let categoryProvider: ActivityCategoryProvider
    private let database: Database
    
    // MARK: - Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let activitySubject = PassthroughSubject<ActivityRecord, Error>()
    
    // MARK: - Initialization
    
    init(accessibilityService: AccessibilityService,
         categoryProvider: ActivityCategoryProvider,
         database: Database) {
        self.accessibilityService = accessibilityService
        self.categoryProvider = categoryProvider
        self.database = database
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() -> AnyPublisher<ActivityRecord, Error> {
        // Implementation details
        return activitySubject.eraseToAnyPublisher()
    }
    
    func getCurrentActivity() -> ActivityRecord? {
        // Implementation details
        return nil
    }
    
    // MARK: - Private Methods
    
    private func processNewActivity(_ activity: RawActivity) {
        // Implementation details
    }
}
```

### Data Storage
- Use GRDB for SQLite interactions
- Implement data migration strategy for version updates
- Create dedicated repositories for each entity type
- Use value types (structs) for database models
- Implement proper error handling and retry logic

### Concurrency Patterns
- Use Swift Concurrency (async/await) for new code
- Use GCD for compatibility with older APIs
- Implement actor model for shared mutable state
- Avoid blocking the main thread
- Use proper synchronization for shared resources

### Background Processing
- Register BackgroundTasks for periodic updates
- Implement proper state restoration
- Minimize battery impact with coalesced updates
- Handle app termination and restart gracefully
- Use power-efficient APIs where possible

### Error Handling Strategy
```swift
enum ServiceError: Error {
    case connectionFailed
    case authenticationFailed
    case resourceNotFound
    case permissionDenied
    case rateLimitExceeded
    case unknown(underlying: Error)
}

func fetchData() async throws -> Data {
    do {
        let result = try await networkService.request(.getData)
        return result
    } catch let error as NetworkError {
        switch error {
        case .unauthorized:
            throw ServiceError.authenticationFailed
        case .notFound:
            throw ServiceError.resourceNotFound
        case .serverError:
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await fetchData()  // Retry once
        default:
            throw ServiceError.unknown(underlying: error)
        }
    }
}
```

### Logging Strategy
- Use structured logging (OSLog)
- Define clear log levels (debug, info, warning, error)
- Include contextual information in log entries
- Implement crash reporting mechanism
- Create troubleshooting logs for user support

## 3. Integration Guidelines

### API Communication
- Use URLSession for network requests
- Implement proper authentication handling
- Create dedicated request/response models
- Handle network errors gracefully
- Implement retry logic with exponential backoff

### Dependency Management
- Use Swift Package Manager for external dependencies
- Minimize third-party dependencies
- Create abstractions around external services
- Version pin all dependencies
- Document dependency purposes and alternatives

### Testing Integration Points
- Create mock implementations of all external services
- Test failure scenarios and edge cases
- Implement integration tests for critical paths
- Use recorded responses for consistent testing

### Security Best Practices
- Store sensitive data in Keychain
- Implement proper credential management
- Use HTTPS for all network communications
- Validate server certificates
- Implement proper input validation
- Follow least privilege principle for permissions
