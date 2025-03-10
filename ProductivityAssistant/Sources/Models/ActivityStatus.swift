import Foundation

/// Represents the current status of user activity for display purposes
enum ActivityStatus {
    case productive
    case neutral
    case distracted
    
    var description: String {
        switch self {
        case .productive:
            return "Productive"
        case .neutral:
            return "Neutral"
        case .distracted:
            return "Distracting"
        }
    }
} 