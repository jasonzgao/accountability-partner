import Foundation

/// Represents different types of applications that can be tracked
enum ApplicationType: String, Codable, CaseIterable {
    /// A desktop application
    case desktopApp = "desktop_app"
    
    /// A browser tab
    case browserTab = "browser_tab"
    
    /// A system process or service
    case systemProcess = "system_process"
    
    /// Human-readable description of the application type
    var displayName: String {
        switch self {
        case .desktopApp:
            return "Desktop Application"
        case .browserTab:
            return "Browser Tab"
        case .systemProcess:
            return "System Process"
        }
    }
    
    /// Icon name for the application type
    var iconName: String {
        switch self {
        case .desktopApp:
            return "app.badge"
        case .browserTab:
            return "globe"
        case .systemProcess:
            return "gear"
        }
    }
    
    /// Checks if the provided application name is a known browser
    static func isBrowser(_ appName: String) -> Bool {
        let browsers = ["Safari", "Google Chrome", "Firefox", "Microsoft Edge", "Opera", "Brave Browser"]
        return browsers.contains { appName.contains($0) }
    }
    
    /// Determines the application type based on the application name
    static func fromApplicationName(_ appName: String) -> ApplicationType {
        if isBrowser(appName) {
            return .browserTab
        } else if appName.starts(with: "com.apple.") || 
                  appName.contains("daemon") || 
                  appName.contains("agent") || 
                  appName == "Finder" || 
                  appName == "SystemUIServer" {
            return .systemProcess
        } else {
            return .desktopApp
        }
    }
} 