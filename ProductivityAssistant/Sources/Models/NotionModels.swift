import Foundation

/// Represents an event from Notion calendar
struct NotionEvent: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let location: String?
    let url: URL?
    let notes: String?
    let attendees: [String]?
    let databaseId: String
    let pageId: String
    let createdTime: Date
    let lastEditedTime: Date
    
    // Helper computed properties
    var isAllDay: Bool {
        let calendar = Calendar.current
        return calendar.isDate(startTime, inSameDayAs: endTime) &&
            calendar.component(.hour, from: startTime) == 0 &&
            calendar.component(.minute, from: startTime) == 0 &&
            calendar.component(.hour, from: endTime) == 23 &&
            calendar.component(.minute, from: endTime) == 59
    }
    
    var isCurrent: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }
    
    var isUpcoming: Bool {
        let now = Date()
        return startTime > now
    }
    
    var isPast: Bool {
        let now = Date()
        return endTime < now
    }
    
    var durationMinutes: Int {
        return Int(endTime.timeIntervalSince(startTime) / 60)
    }
    
    var timeRangeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        if isAllDay {
            return "All day"
        } else {
            return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
        }
    }
}

/// Represents a Notion database used for calendar events
struct NotionDatabase: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let lastSyncedTime: Date?
    let eventCount: Int
    
    init(id: String, title: String, lastSyncedTime: Date? = nil, eventCount: Int = 0) {
        self.id = id
        self.title = title
        self.lastSyncedTime = lastSyncedTime
        self.eventCount = eventCount
    }
}

/// Represents the authentication state for Notion
struct NotionAuthState: Codable, Equatable {
    let accessToken: String
    let workspaceId: String?
    let workspaceName: String?
    let workspaceIcon: String?
    let userId: String?
    let botId: String?
    let expiresAt: Date
    
    var isValid: Bool {
        return Date() < expiresAt
    }
}

/// Error types for Notion integration
enum NotionIntegrationError: Error {
    case networkError(String)
    case authenticationFailed
    case notAuthenticated
    case parseError
    case apiError(code: Int, message: String)
    case rateLimitExceeded
    case databaseNotFound
    case invalidToken
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed:
            return "Authentication failed with Notion"
        case .notAuthenticated:
            return "Not authenticated with Notion"
        case .parseError:
            return "Failed to parse Notion data"
        case .apiError(let code, let message):
            return "Notion API error (\(code)): \(message)"
        case .rateLimitExceeded:
            return "Notion API rate limit exceeded"
        case .databaseNotFound:
            return "Calendar database not found in Notion"
        case .invalidToken:
            return "Invalid or expired Notion token"
        case .unknown:
            return "An unknown error occurred with Notion integration"
        }
    }
} 