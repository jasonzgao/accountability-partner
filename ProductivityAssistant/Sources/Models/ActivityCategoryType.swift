import Foundation

/// Represents the type of an activity category in the database
enum ActivityCategoryType: String, Codable, CaseIterable {
    /// Productive activities (work, learning, etc.)
    case productive = "productive"
    
    /// Neutral activities (email, planning, etc.)
    case neutral = "neutral"
    
    /// Distracting activities (social media, entertainment, etc.)
    case distracting = "distracting"
    
    /// Human-readable description of the category type
    var displayName: String {
        switch self {
        case .productive:
            return "Productive"
        case .neutral:
            return "Neutral"
        case .distracting:
            return "Distracting"
        }
    }
    
    /// Default hex color for this category type
    var defaultHexColor: String {
        switch self {
        case .productive:
            return "#4CAF50"  // Green
        case .neutral:
            return "#FFC107"  // Amber
        case .distracting:
            return "#F44336"  // Red
        }
    }
    
    /// Converts to an ActivityCategory
    var toActivityCategory: ActivityCategory {
        switch self {
        case .productive:
            return .productive
        case .neutral:
            return .neutral
        case .distracting:
            return .distracting
        }
    }
    
    /// Creates an ActivityCategoryType from an ActivityCategory
    static func from(_ category: ActivityCategory) -> ActivityCategoryType {
        switch category {
        case .productive:
            return .productive
        case .neutral:
            return .neutral
        case .distracting:
            return .distracting
        case .custom:
            // Default custom categories to neutral, but in a real app,
            // this would be determined by user selection
            return .neutral
        }
    }
} 