# App Flow Document

## 1. User Journey Overview

### Initial Setup
1. User downloads and installs the macOS app
2. App requests necessary permissions (accessibility, notifications, calendar access)
3. User completes onboarding wizard:
   - Connects to Things 3 and Notion Calendar
   - Customizes app/website categorization
   - Sets up initial goals and habits
   - Configures accountability mechanisms

### Daily Usage Flow
1. App starts automatically at login and runs in background
2. Morning summary notification shows today's plan
3. Real-time monitoring tracks application/website usage
4. Contextual notifications appear based on:
   - Upcoming calendar events
   - Due tasks approaching deadline
   - Prolonged distraction periods
   - Goal progress updates
5. User can check status via menu bar icon at any time
6. End-of-day summary provides accomplishments and areas for improvement

## 2. Core Interaction Flows

### Menu Bar Interaction
```
Menu Bar Icon Click → 
  Quick View Panel
    ├── Current Status (Productive/Neutral/Distracted)
    ├── Today's Progress Summary
    ├── Current/Next Calendar Event
    ├── Quick Actions:
    │   ├── Start Focus Session
    │   ├── Log Distraction
    │   ├── Mark Task Complete
    │   └── Open Chat with AI Coach
    └── Settings Button → Full Settings Panel
```

### Distraction Detection Flow
```
App Detects Distracting Activity →
  Check Context (Calendar, Current Tasks) →
    If Valid Reason for Distraction →
      No Action
    Else If Short Distraction (<5 min) →
      No Action
    Else If Medium Distraction (5-15 min) →
      Gentle Nudge Notification
    Else If Long Distraction (>15 min) →
      Strong Nudge + Suggestion to Redirect →
        User Action:
          ├── Dismiss (Continue Distraction)
          ├── Redirect to Planned Task
          └── Modify Plan (Reschedule Tasks)
```

### Goal Tracking Flow
```
User Creates Goal →
  System Monitors Related Activities →
    Daily/Weekly Assessment →
      If Goal Met →
        Congratulatory Notification + Reward Trigger
      Else If Goal Progress Acceptable →
        Encouraging Notification
      Else If Goal Falling Behind →
        Warning Notification + Suggestion →
          User Action:
            ├── Recommit to Goal
            ├── Modify Goal Parameters
            └── Consult AI Coach for Help
```

### AI Coaching Interaction
```
User Opens Chat →
  System Provides Context Summary →
    User Inputs Question/Concern →
      AI Analyzes:
        ├── Historical Data
        ├── Current Goals
        ├── Recent Challenges
        └── Successful Patterns
      AI Responds with:
        ├── Insights
        ├── Suggestions
        ├── Follow-up Questions
        └── Actionable Steps
```

## 3. Key Screens & Components

### Menu Bar Quick View
- Current status indicator (color-coded)
- Time spent today (productive vs. distracting)
- Progress bars for active goals
- Next upcoming event/task

### Settings Panel
- General preferences
- Categorization rules
- Integration settings
- Notification preferences
- Goals & habits management
- Accountability mechanisms

### Reports View
- Daily/weekly/monthly tabs
- Time allocation charts
- Productivity trends
- Goal completion metrics
- Habit streaks visualization

### Chat Interface
- Conversation history
- Message input field
- Quick prompt suggestions
- Data visualization widgets

### Notification Types
- Distraction alerts (overlay)
- Task reminders (standard notification)
- Goal updates (standard notification)
- Daily summaries (rich notification)

## 4. State Management

### User States
- Focused: Actively working on productive tasks
- Distracted: Engaged with categorized distractions
- Neutral: Using uncategorized or mixed-purpose applications
- AFK: Away from keyboard (no activity for >5 minutes)
- In Meeting: Calendar event in progress

### Goal States
- On Track: Progress aligned with expectations
- At Risk: Slightly behind expected progress
- Off Track: Significantly behind expected progress
- Completed: Success criteria met
- Failed: Deadline passed without completion

### System States
- Active Monitoring: Normal operation
- Paused: Monitoring temporarily disabled
- Focus Mode: Enhanced distraction blocking active
- Low Power: Reduced functionality to conserve battery
