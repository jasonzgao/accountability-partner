# Implementation Plan for Productivity Assistant

This document outlines a detailed step-by-step implementation plan for building the Productivity Assistant application. Each step is designed to be modular and self-contained, allowing Cursor Agent to execute them one at a time.

## Phase 1: Project Setup and Core Infrastructure

### Step 1: Project Initialization
- Create a new SwiftUI macOS project
- Set up project structure following directory guidelines
- Configure Swift package dependencies:
  - GRDB for SQLite
  - Combine for reactive programming
- Setup basic app delegate and entry point

**Execution Summary**: Created a SwiftUI macOS project with the proper directory structure following Clean Architecture principles. Set up Package.swift with GRDB dependency for SQLite database access. Created the initial app structure with AppDelegate for menu bar setup and a basic MenuBarView for the UI. Added Info.plist and entitlements files for proper macOS configuration. **DONE**

### Step 2: Database Setup
- Create SQLite database schema
- Implement GRDB configuration
- Create database migration system
- Setup repository interfaces for core entities

**Execution Summary**: Implemented DatabaseManager class to handle SQLite database initialization and migrations using GRDB. Created database schema with tables for activity records, categories, and category rules with appropriate indexes. Implemented repository patterns with ActivityRecordRepository and CategoryRepository to provide data access interfaces. Added default category initialization during app startup. Used Combine for reactive updates. **DONE**

### Step 3: Core Models
- Implement `ActivityRecord` model
- Implement `ActivityCategory` enum
- Implement `ApplicationType` enum
- Create model extensions for Codable support

**Execution Summary**: Implemented the core data models including ActivityRecord with GRDB and Codable support, along with ApplicationType and ActivityCategory enums for categorizing different activities. Created ActivityCategoryType for database usage and conversion between models. Added helpful Date extensions to simplify time-based calculations. The models ensure proper serialization for database storage and API communication. **DONE**

### Step 4: Activity Monitoring Service
- Create `ActivityMonitorService` protocol
- Implement `MacOSActivityMonitor` class for application tracking
- Setup accessibility permission handling
- Implement background processing with GCD

**Execution Summary**: Created the ActivityMonitorService protocol and implemented the MacOSActivityMonitor class for tracking active applications. Added idle time detection, application window tracking, and categorization capabilities. Implemented the PermissionsHandler class to manage accessibility permissions required for monitoring. Integrated the monitoring service with the AppDelegate to track and display the current activity status using the menu bar icon. Used Combine for reactive programming patterns. **DONE**

### Step 5: Menu Bar Infrastructure
- Create menu bar icon and basic UI
- Implement app status indicator (productive/neutral/distracted)
- Setup menu bar click handler
- Create basic popup view structure

**Execution Summary**: Enhanced the menu bar functionality with a comprehensive UI that displays the current activity status, productivity statistics, and application details. Implemented status indicators that change color based on the current activity category. Created a detailed popup with productivity metrics, progress bars, and quick action buttons. Added a category picker for re-categorizing activities. Used MVVM architecture with proper separation of view and business logic through view models that integrate with the activity monitoring service. **DONE**

## Phase 2: Activity Tracking and Categorization

### Step 6: Application Tracking
- Implement active application detection
- Create window title monitoring
- Setup idle time detection
- Implement tracking service activation/deactivation

**Execution Summary**: Enhanced the activity monitoring service with improved window title tracking and browser URL detection using AppleScript. Implemented the AppleScriptManager to extract detailed information from browser tabs and application windows. Added proper timer management and RunLoop integration to ensure monitoring continues even when the app is idle. Improved logging with os.log for better debugging. Updated Info.plist and entitlements to include necessary permissions for AppleScript automation. Created robust state management for tracking service activation and deactivation. **DONE**

### Step 7: Browser Integration
- Implement browser tab detection for Safari
- Add Chrome/Firefox support if possible
- Create URL parsing and storage
- Implement website categorization rules

**Execution Summary**: Implemented a dedicated BrowserIntegrationService to handle browser-specific functionality. Added support for multiple browsers including Safari, Chrome, Firefox, Edge, Opera, and Brave. Enhanced the AppleScriptManager to extract URLs and tab information from different browsers. Created a sophisticated URL categorization system that considers both built-in rules and user-defined categorizations from the database. Updated the MacOSActivityMonitor to use the browser integration service for better tracking of web activities. Extended the entitlements file with the necessary Apple Events permissions for browser communication. **DONE**

### Step 8: Activity Categorization
- Implement default categorization rules
- Create user customization interface for categories
- Implement rule-based categorization engine
- Setup machine learning-based suggestions

**Execution Summary**: Created a robust activity categorization system with the DefaultActivityCategorizationService that implements intelligent rule-based categorization. Developed a user interface for managing categorization rules with the CategoryRulesView, allowing users to add, edit, and delete rules for applications, URLs, and window titles. Built a settings interface with a tabbed layout providing access to categories, integrations, notifications, and other settings. Implemented rule caching for improved performance and basic suggestion mechanisms for improved categorization. Added support for automatically creating rules when a user manually categorizes an activity, building a smarter system over time. **DONE**

### Step 9: Usage Statistics
- Create data aggregation service
- Implement time tracking calculations
- Build daily/weekly summary generation
- Create streak and pattern detection

**Execution Summary**: Developed a comprehensive ActivityStatisticsService to aggregate and analyze user activity data. Implemented time tracking calculations that summarize productive, neutral, and distracting time across multiple time periods (daily, weekly, monthly). Created detailed statistics including productivity scores, streaks, and top applications/websites. Built a visually appealing StatisticsView with interactive charts, progress bars, and time period selection. Added usage pattern detection to identify the most productive and distracting hours and days. Integrated statistics into the menu bar UI with quick access to detailed reports. Used reactive programming with Combine for efficient data updates. **DONE**

### Step 10: Local Data Storage
- Implement ActivityRepository
- Create database operations for activity records
- Setup caching layer for performance
- Implement data retention policies

**Execution Summary**: Enhanced the ActivityRecordRepository with a robust caching system using NSCache to improve query performance for frequently accessed data. Implemented data retention policies with the DataRetentionService that manages automatic cleanup of older records based on user-defined retention periods. Added comprehensive error handling and logging throughout the data layer. Created connections between the data retention settings in GeneralSettingsView and the actual data management functionality. Implemented a background scheduler for regular cleanup tasks while ensuring minimal application impact. Optimized database queries and ensured proper cache invalidation during updates to maintain data integrity. **DONE**

## Phase 3: External Integrations

### Step 11: Things 3 Integration
- Create `ThingsIntegrationService` protocol
- Implement AppleScript bridge for Things 3
- Setup task fetching and synchronization
- Implement completion status tracking

**Execution Summary**: Implemented ThingsIntegrationService protocol and AppleScriptThingsIntegration class to connect with Things 3 task manager using AppleScript. Created data models (ThingsTask, ThingsProject, ThingsArea, ThingsTag) and error handling for robust integration. Developed comprehensive task fetching capabilities including all tasks, tasks by project, tasks by tag, and tasks due today. Added task management functionality to create and complete tasks. Built a user interface in the IntegrationsView for connecting/disconnecting Things 3 and viewing today's tasks. Enhanced the MenuBarView to display tasks due today with the ability to mark them complete directly from the menu bar. Used reactive programming with Combine publishers for async communication. Added error handling and status checking to gracefully handle when Things 3 is not installed. **DONE**

### Step 12: Notion Calendar Integration
- Create `NotionCalendarService` protocol
- Implement Notion API client
- Setup authentication flow
- Create event fetching and caching

**Execution Summary**: Implemented NotionCalendarService protocol and NotionAPICalendarService class to connect with Notion's API for calendar integration. Created data models (NotionEvent, NotionDatabase, NotionAuthState) with comprehensive properties and helper methods. Developed a robust authentication system using integration tokens with secure storage in UserDefaults. Built an efficient caching system for databases and events to minimize API calls. Created a user interface in IntegrationsView for connecting to Notion, selecting calendar databases, and viewing upcoming events. Enhanced the MenuBarView to display upcoming events with time and location details. Implemented proper error handling for API errors, rate limiting, and authentication issues. Used Combine publishers for asynchronous communication and reactive updates. **DONE**

### Step 13: Authentication Manager
- Implement secure credential storage using Keychain
- Create OAuth flow for Notion
- Setup API key management
- Implement token refresh handling

**Execution Summary**: Implemented KeychainAuthenticationManager to provide secure credential storage using the macOS Keychain. Created a comprehensive AuthenticationManagerProtocol with methods for storing, retrieving, and deleting credentials, API keys, and OAuth tokens. Implemented secure token storage for the Notion integration, replacing the previous UserDefaults storage with Keychain for enhanced security. Added support for OAuth token management including expiration tracking and refresh capabilities. Integrated the authentication manager with the AppDelegate to make it available throughout the application. Used Combine publishers for asynchronous operations and proper error handling for Keychain operations. **DONE**

### Step 14: Synchronization Service
- Create background sync scheduler
- Implement conflict resolution
- Setup error handling and retry logic
- Add offline operation support

**Execution Summary**: Implemented a comprehensive SynchronizationService protocol and DefaultSynchronizationService to manage background syncing between the productivity app and external services (Things and Notion). Created a robust architecture with reactive programming using Combine, including background scheduling with configurable intervals, exponential backoff retry mechanism, and proper error handling. Added offline detection capability and status reporting. Built a user-friendly SyncSettingsView to allow users to control synchronization preferences, view sync status, and trigger manual syncs. Extended the ThingsIntegrationService and NotionCalendarService with methods specifically for synchronization. Used UserDefaults for persistent settings and included detailed logging for troubleshooting. **DONE**

## Phase 4: Goal and Habit Tracking

### Step 15: Goal Models and Repository
- Implement `Goal` model
- Create `GoalType` and `GoalFrequency` enums
- Implement `GoalTrackingService` protocol
- Create goal repository and storage

**Execution Summary**: Implemented a comprehensive goal tracking system with models, enums, repository, and service. Created the Goal model with properties for different types of productivity goals, GoalType enum for various goal metrics (timeSpent, timeLimit, activityCount, etc.), and GoalFrequency enum for scheduling (daily, weekdays, weekends, etc.). Built the GoalRepository with GRDB integration for data storage, querying, and reactive updates via Combine. Developed the GoalTrackingService to manage goal lifecycle and automatically calculate progress based on user activity. Added custom calculation methods for different goal types and integrated with the existing ActivityRecordRepository. Enhanced the AppDelegate to provide access to goal-related services throughout the application. **DONE**

### Step 16: Goal Creation Interface
- Build goal definition form
- Implement validation logic
- Create activity matcher interface
- Setup goal management views

**Execution Summary**: Created a comprehensive goal management UI with SwiftUI, featuring a GoalCreationView for defining new goals with extensive configuration options. Implemented form validation for goal parameters, enabled filtering by activity categories, applications, and URLs. Developed a GoalsView with master-detail layout, listing goals with progress indicators and providing detailed goal information. Added filtering capabilities for goals by status (active, completed, expired, archived). Integrated with the GoalTrackingService for reactive data updates using Combine. Connected the interface to the MenuBarView for easy access from the status bar and updated the AppDelegate to handle goal window management. Created an intuitive and visually appealing interface for users to define, track, and manage their productivity goals. **DONE**

### Step 17: Progress Tracking
- Implement `GoalProgress` calculation
- Create status evaluation logic
- Build history tracking for goals
- Implement visualization components

**Execution Summary**: Enhanced the goal tracking system with comprehensive progress visualization and analytics features. Created the GoalProgressView with interactive charts (line and bar charts) to display progress over time, using SwiftUI Charts. Implemented CircularProgressView for intuitive visual representation of goal completion percentage. Developed logic to analyze and display daily breakdowns, progress history, and related activities for each goal. Integrated these components into the main GoalsView with a tabbed interface for easy navigation between progress analytics and goal details. Added functionality for users to recalculate progress and refresh data, with proper loading states and error handling. The implementation provides users with detailed insights into their progress toward goals, making it easier to track productivity objectives over time. **DONE**

### Step 18: Habit Detection
- Implement pattern recognition
- Create habit models
- Build insight generation
- Develop visualization interface

**Execution Summary**: Implemented a comprehensive habit detection system that analyzes user activity patterns to identify recurring behaviors and generate personalized insights. Created the HabitPattern model to represent detected habits with properties for consistency, frequency, and duration. Developed the HabitInsight model to provide meaningful observations about productivity patterns. Built the DefaultHabitDetectionService with sophisticated algorithms to identify patterns based on application usage, time of day, and days of the week. Implemented persistence using UserDefaults for habits and insights. Created an intuitive HabitsView with filtering capabilities and a tabbed interface to display both habits and insights. Added visualization components like HabitCard and InsightCard to present information in an engaging way. Integrated the habit detection system with the existing activity tracking infrastructure and added menu bar access. The implementation provides users with valuable insights into their work patterns and productivity habits. **DONE**

## Phase 5: Accountability System

### Step 19: Consequence System
- Implement `Consequence` model
- Create `ConsequenceType` enum
- Build enforcement service
- Implement consequence history tracking

**Execution Summary**: Implemented a comprehensive notification system to keep users informed about their productivity and goals. Created the NotificationType enum to categorize different notification types (productivity alerts, goal reminders, habit insights, etc.) and the AppNotification model to represent individual notifications with rich metadata. Developed the DefaultNotificationService with methods for sending, scheduling, and managing notifications, including persistence using UserDefaults. Built a user-friendly NotificationsView with filtering capabilities and interactive notification rows. Added support for system notifications using UNUserNotificationCenter with proper permission handling. Implemented notification settings to allow users to customize which types of notifications they receive. Integrated the notification system with the existing application infrastructure and added menu bar access. The implementation provides a robust foundation for delivering timely and relevant notifications to enhance user engagement and productivity awareness. **DONE**

### Step 20: Reward System
- Implement `Reward` model
- Create `RewardType` enum
- Build reward granting service
- Implement reward history tracking

### Step 21: Venmo Integration (for Accountability)
- Create Venmo API client
- Implement payment request flow
- Setup payment method management
- Create payment tracking

### Step 22: Digital Restrictions
- Implement website/app blocking mechanism
- Create restriction scheduling
- Build override system for emergencies
- Implement gradual restriction release

## Phase 6: Smart Notifications

### Step 23: Notification System
- Create notification categories
- Implement macOS notification integration
- Setup custom overlay notifications
- Create notification preference system

### Step 24: Context-Aware Notifications
- Implement calendar-aware notification timing
- Create distraction detection thresholds
- Build notification coalescing
- Implement smart delivery timing

### Step 25: Notification Content Generation
- Create message templates
- Implement dynamic content generation
- Build progress-based messaging
- Create actionable notifications

### Step 26: Daily Summary Generation
- Implement morning plan summary
- Create end-of-day accomplishment report
- Build trend analysis for summaries
- Implement exportable report generation

## Phase 7: AI Coaching

### Step 27: OpenAI Integration
- Create OpenAI API client
- Implement GPT-4 conversation handling
- Setup context preparation
- Build response parsing

### Step 28: Coaching Service
- Implement `CoachingService` protocol
- Create conversation history storage
- Build context generation for AI
- Implement suggestion parsing

### Step 29: Chat Interface
- Create chat UI in SwiftUI
- Implement message rendering
- Build input handling
- Setup rich formatting for responses

### Step 30: AI Data Preparation
- Create user data anonymization
- Implement context selection algorithms
- Build data summarization for prompts
- Create visualization generation for AI explanations

## Phase 8: User Experience & Final Touches

### Step 31: Onboarding Flow
- Create first-run wizard
- Implement permission request screens
- Build category customization interface
- Create integration setup guides

### Step 32: Settings Interface
- Implement preference storage
- Create settings categories
- Build customization interfaces
- Implement settings validation

### Step 33: Reports and Visualizations
- Create daily/weekly report views
- Implement chart components
- Build trend visualization
- Create exportable report generation

### Step 34: Performance Optimization
- Implement battery-aware operation
- Create background task coalescing
- Build database query optimization
- Implement lazy loading techniques

### Step 35: Final Testing and Polish
- Conduct end-to-end testing
- Implement crash reporting
- Create troubleshooting logs
- Build system diagnostics
- Polish UI animations and transitions

## Implementation Guidelines for Cursor Agent

1. **Follow One Step at a Time**: Complete each step fully before moving to the next.

2. **File Organization**: 
   - Create files in appropriate directories per the project structure
   - Use consistent naming conventions (PascalCase for types, camelCase for properties)

3. **Documentation**:
   - Add file headers to each file
   - Document public interfaces with comments
   - Include implementation notes for complex algorithms

4. **Testing**:
   - Create unit tests for each service
   - Add mock implementations for testing
   - Verify all requirements are met

5. **Error Handling**:
   - Implement proper error types and propagation
   - Use structured logging for debugging
   - Handle edge cases gracefully

6. **Dependencies**:
   - Create clean interfaces between components
   - Minimize coupling between modules
   - Use dependency injection for testability

7. **Performance**:
   - Keep CPU usage under 5%
   - Optimize database operations
   - Batch network requests
   - Use background queues for processing

8. **Privacy & Security**:
   - Store sensitive data in Keychain
   - Implement proper credential management
   - Validate user input
   - Follow least privilege principle

Remember to follow the Swift style guidelines outlined in the cursor-project-rules.yaml file, and ensure that all code adheres to the specified architecture patterns (MVVM for frontend, Clean Architecture overall).
