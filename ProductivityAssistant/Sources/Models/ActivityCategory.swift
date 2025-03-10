import Foundation
import SwiftUI

/// Represents the productivity category of an activity
enum ActivityCategory: String, Codable, CaseIterable {
    /// Productive activities (work, learning, etc.)
    case productive = "productive"
    
    /// Neutral activities (email, planning, etc.)
    case neutral = "neutral"
    
    /// Distracting activities (social media, entertainment, etc.)
    case distracting = "distracting"
    
    /// Custom category (user-defined)
    case custom = "custom"
    
    /// Human-readable description of the category
    var displayName: String {
        switch self {
        case .productive:
            return "Productive"
        case .neutral:
            return "Neutral"
        case .distracting:
            return "Distracting"
        case .custom:
            return "Custom"
        }
    }
    
    /// Color associated with the category
    var color: Color {
        switch self {
        case .productive:
            return Color.green
        case .neutral:
            return Color.yellow
        case .distracting:
            return Color.red
        case .custom:
            return Color.blue
        }
    }
    
    /// Icon name for the category
    var iconName: String {
        switch self {
        case .productive:
            return "checkmark.circle.fill"
        case .neutral:
            return "minus.circle.fill"
        case .distracting:
            return "exclamationmark.circle.fill"
        case .custom:
            return "tag.circle.fill"
        }
    }
    
    /// Returns a category based on an application or website
    static func categorize(applicationName: String, url: URL? = nil, windowTitle: String? = nil) -> ActivityCategory {
        // Default categorizations - in a real app, these would be more sophisticated
        // and would use user preferences and machine learning
        
        // Productivity apps
        let productiveApps = ["Xcode", "Visual Studio", "IntelliJ", "PyCharm", "Things", "OmniFocus"]
        let productiveDomains = ["github.com", "stackoverflow.com", "docs.swift.org", "developer.apple.com"]
        
        // Distracting apps
        let distractingApps = ["Netflix", "YouTube", "Twitter", "Facebook", "Instagram", "TikTok", "Reddit"]
        let distractingDomains = ["netflix.com", "youtube.com", "twitter.com", "facebook.com", "instagram.com", "tiktok.com", "reddit.com"]
        
        // Check if the app is in our known lists
        if productiveApps.contains(where: { applicationName.contains($0) }) {
            return .productive
        }
        
        if distractingApps.contains(where: { applicationName.contains($0) }) {
            return .distracting
        }
        
        // Check URL for browser activities
        if let url = url, let host = url.host {
            if productiveDomains.contains(where: { host.contains($0) }) {
                return .productive
            }
            
            if distractingDomains.contains(where: { host.contains($0) }) {
                return .distracting
            }
        }
        
        // Default to neutral for unknown applications
        return .neutral
    }
} 