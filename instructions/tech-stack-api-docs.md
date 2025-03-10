# Tech Stack & API Documentation

## 1. Technology Stack

### Frontend
- **Framework**: SwiftUI for native macOS UI
- **State Management**: Combine framework
- **UI Components**: Native macOS components + custom widgets
- **Charts/Visualization**: Swift Charts library

### Backend/Core
- **Language**: Swift 5.8+
- **Database**: SQLite with GRDB.swift wrapper
- **Background Processing**: GCD (Grand Central Dispatch)
- **AI Integration**: OpenAI API (GPT-4)
- **Analytics**: Local analytics engine (no third-party tracking)

### System Integration
- **OS Monitoring**: AppKit + Accessibility API
- **Notifications**: UserNotifications framework
- **Background Processing**: BackgroundTasks framework
- **Calendar Access**: EventKit framework

## 2. Core APIs & Data Models

### Application Monitoring API

```swift
struct ActivityRecord {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let applicationType: ApplicationType
    let applicationName: String
    let windowTitle: String?
    let url: URL?
    let category: ActivityCategory
}

enum ApplicationType {
    case desktopApp
    case browserTab
    case systemProcess
}

enum ActivityCategory {
    case productive
    case neutral
    case distracting
    case custom(String)
}

protocol ActivityMonitorService {
    func startMonitoring() -> AnyPublisher<ActivityRecord, Error>
    func stopMonitoring()
    func getCurrentActivity() -> ActivityRecord?
    func getActivityHistory(from: Date, to: Date) -> [ActivityRecord]
    func categorizeActivity(_ activity: ActivityRecord, as category: ActivityCategory)
}
```

### Things 3 Integration API

```swift
struct ThingsTask {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let tags: [String]
    let project: String?
    let completed: Bool
    let checklist: [ThingsChecklistItem]?
}

struct ThingsChecklistItem {
    let title: String
    let completed: Bool
}

protocol ThingsIntegrationService {
    func fetchTasks() -> [ThingsTask]
    func fetchTasksByProject(project: String) -> [ThingsTask]
    func fetchTasksByTag(tag: String) -> [ThingsTask]
    func fetchTasksDueToday() -> [ThingsTask]
    func markTaskComplete(id: String) -> Bool
    func createTask(title: String, notes: String?, dueDate: Date?, 
                   project: String?, tags: [String]?) -> ThingsTask?
}
```

### Notion Calendar Integration API

```swift
struct NotionEvent {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let location: String?
    let url: URL?
    let notes: String?
    let attendees: [String]?
}

protocol NotionCalendarService {
    func authenticate(token: String) -> AnyPublisher<Bool, Error>
    func fetchEvents(from: Date, to: Date) -> AnyPublisher<[NotionEvent], Error>
    func fetchUpcomingEvents(limit: Int) -> AnyPublisher<[NotionEvent], Error>
    func getCurrentEvent() -> NotionEvent?
    func getNextEvent() -> NotionEvent?
}
```

### Goal Tracking API

```swift
struct Goal {
    let id: UUID
    let title: String
    let description: String?
    let type: GoalType
    let frequency: GoalFrequency
    let targetValue: Double
    let startDate: Date
    let endDate: Date?
    let associatedActivities: [ActivityMatcher]
    let consequences: [Consequence]?
    let rewards: [Reward]?
}

enum GoalType {
    case timeSpent
    case taskCompletion
    case avoidance
}

enum GoalFrequency {
    case daily
    case weekly
    case monthly
    case custom(DateInterval)
}

struct ActivityMatcher {
    let applicationType: ApplicationType?
    let applicationName: String?
    let urlPattern: String?
    let category: ActivityCategory?
}

protocol GoalTrackingService {
    func createGoal(_ goal: Goal) -> UUID
    func updateGoal(_ goal: Goal) -> Bool
    func deleteGoal(id: UUID) -> Bool
    func getGoals() -> [Goal]
    func getGoalProgress(id: UUID) -> GoalProgress
    func checkGoalCompletion(id: UUID) -> Bool
}

struct GoalProgress {
    let goalId: UUID
    let currentValue: Double
    let targetValue: Double
    let percentComplete: Double
    let status: GoalStatus
    let history: [ProgressDataPoint]
}

enum GoalStatus {
    case onTrack
    case atRisk
    case offTrack
    case completed
    case failed
}
```

### Accountability API

```swift
struct Consequence {
    let id: UUID
    let type: ConsequenceType
    let description: String
    let severity: Double // 0.0-1.0 scale
    let parameters: [String: Any]
}

enum ConsequenceType {
    case payment
    case restriction
    case notification
    case custom
}

struct Reward {
    let id: UUID
    let type: RewardType
    let description: String
    let magnitude: Double // 0.0-1.0 scale
    let parameters: [String: Any]
}

enum RewardType {
    case unlockActivity
    case freeTime
    case custom
}

protocol AccountabilityService {
    func enforceConsequence(_ consequence: Consequence) -> Bool
    func grantReward(_ reward: Reward) -> Bool
    func getConsequenceHistory() -> [ConsequenceRecord]
    func getRewardHistory() -> [RewardRecord]
}
```

### AI Coaching API

```swift
struct CoachingQuery {
    let text: String
    let context: CoachingContext?
}

struct CoachingContext {
    let relevantGoals: [UUID]?
    let timeRange: DateInterval?
    let activityFocus: ActivityCategory?
}

struct CoachingResponse {
    let messageId: UUID
    let text: String
    let suggestions: [CoachingSuggestion]?
    let followUpQuestions: [String]?
}

struct CoachingSuggestion {
    let title: String
    let description: String
    let actionType: CoachingActionType
    let parameters: [String: Any]?
}

enum CoachingActionType {
    case modifyGoal
    case startFocusSession
    case rescheduleTask
    case adjustCategory
    case learnTechnique
}

protocol CoachingService {
    func submitQuery(_ query: CoachingQuery) -> AnyPublisher<CoachingResponse, Error>
    func getConversationHistory() -> [CoachingQuery: CoachingResponse]
    func clearConversationHistory() -> Bool
}
```

## 3. External API Integrations

### OpenAI GPT-4 API
- **Purpose**: Powers the AI coaching feature
- **Authentication**: API key stored in macOS Keychain
- **Endpoints**:
  - `/v1/chat/completions` - Primary endpoint for conversation
- **Rate Limits**: Maximum 3 requests per minute
- **Error Handling**: Fallback to cached responses if API unavailable

### Venmo API (for Accountability)
- **Purpose**: Process payments for financial consequences
- **Authentication**: OAuth flow with user credentials
- **Endpoints**:
  - `/v1/payments` - Create payment
  - `/v1/payment-methods` - List available payment methods
- **Security**: Minimal payment scope, user confirmation required

### Things 3 AppleScript API
- **Purpose**: Task management integration
- **Method**: NSAppleScript execution with proper sandboxing permissions
- **Key Functions**:
  - `get to dos` - Retrieve tasks
  - `make new to do` - Create tasks
  - `set completed of to do` - Mark tasks complete
- **Error Handling**: Retry logic for AppleScript execution failures

### Notion API
- **Purpose**: Calendar integration
- **Authentication**: OAuth flow with integration token
- **Endpoints**:
  - `/v1/databases` - Query calendar database
  - `/v1/pages` - Get event details
- **Caching Strategy**: Cache events with 15-minute refresh interval
