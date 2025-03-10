import Foundation

/// Represents a task from Things 3
struct ThingsTask: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let tags: [String]
    let project: String?
    let completed: Bool
    let checklist: [ThingsChecklistItem]?
    let creationDate: Date
    let modificationDate: Date
    
    // Helper computed properties
    var isOverdue: Bool {
        guard let dueDate = dueDate, !completed else { return false }
        return dueDate < Date()
    }
    
    var isDueToday: Bool {
        guard let dueDate = dueDate, !completed else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    
    var isDueTomorrow: Bool {
        guard let dueDate = dueDate, !completed else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }
    
    var checklistProgress: Double {
        guard let checklist = checklist, !checklist.isEmpty else { return 0.0 }
        let completedItems = checklist.filter { $0.completed }.count
        return Double(completedItems) / Double(checklist.count)
    }
}

/// Represents a checklist item within a Things 3 task
struct ThingsChecklistItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let completed: Bool
}

/// Represents a project from Things 3
struct ThingsProject: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let notes: String?
    let tags: [String]
    let area: String?
    let taskCount: Int
    let completedTaskCount: Int
    
    // Helper computed property
    var progress: Double {
        guard taskCount > 0 else { return 0.0 }
        return Double(completedTaskCount) / Double(taskCount)
    }
}

/// Represents an area from Things 3
struct ThingsArea: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let projectCount: Int
}

/// Represents a tag from Things 3
struct ThingsTag: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let taskCount: Int
}

/// Error types for Things 3 integration
enum ThingsIntegrationError: Error {
    case scriptExecutionFailed
    case parseError
    case notInstalled
    case permissionDenied
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .scriptExecutionFailed:
            return "Failed to execute AppleScript for Things 3"
        case .parseError:
            return "Failed to parse Things 3 data"
        case .notInstalled:
            return "Things 3 is not installed on this computer"
        case .permissionDenied:
            return "Permission to access Things 3 was denied"
        case .unknown:
            return "An unknown error occurred with Things 3 integration"
        }
    }
} 