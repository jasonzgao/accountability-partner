import Foundation
import AppKit
import os.log

/// Manages the execution of AppleScripts for the application
final class AppleScriptManager {
    // MARK: - Properties
    
    static let shared = AppleScriptManager()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "AppleScript")
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Gets the URL from the current tab in a browser
    func getBrowserURL(browserName: String) -> URL? {
        var script = ""
        
        switch browserName {
        case let name where name.contains("Safari"):
            script = """
            tell application "Safari"
                if it is running then
                    try
                        tell front window
                            set currentURL to URL of current tab
                            return currentURL
                        end tell
                    on error
                        return ""
                    end try
                else
                    return ""
                end if
            end tell
            """
        case let name where name.contains("Chrome"):
            script = """
            tell application "Google Chrome"
                if it is running then
                    try
                        tell front window to set currentURL to URL of active tab
                        return currentURL
                    on error
                        return ""
                    end try
                else
                    return ""
                end if
            end tell
            """
        case let name where name.contains("Firefox"):
            script = """
            tell application "Firefox"
                if it is running then
                    try
                        tell front window to set currentURL to URL of active tab
                        return currentURL
                    on error
                        return ""
                    end try
                else
                    return ""
                end if
            end tell
            """
        default:
            return nil
        }
        
        return executeStringResult(script).flatMap { URL(string: $0) }
    }
    
    /// Gets the title of the current window for an application
    func getWindowTitle(for appName: String) -> String? {
        let script = """
        tell application "\(appName)"
            if it is running then
                try
                    set windowTitle to name of front window
                    return windowTitle
                on error
                    return ""
                end try
            else
                return ""
            end if
        end tell
        """
        
        return executeStringResult(script)
    }
    
    /// Gets all open tabs in a browser
    func getAllBrowserTabs(browserName: String) -> [(title: String, url: URL)]? {
        var script = ""
        
        switch browserName {
        case let name where name.contains("Safari"):
            script = """
            tell application "Safari"
                if it is running then
                    set tabData to {}
                    
                    try
                        repeat with w in windows
                            repeat with t in tabs of w
                                set tabInfo to {title:name of t, url:URL of t}
                                copy tabInfo to end of tabData
                            end repeat
                        end repeat
                        
                        return tabData
                    on error
                        return {}
                    end try
                else
                    return {}
                end if
            end tell
            """
        case let name where name.contains("Chrome"):
            script = """
            tell application "Google Chrome"
                if it is running then
                    set tabData to {}
                    
                    try
                        repeat with w in windows
                            repeat with t in tabs of w
                                set tabInfo to {title:title of t, url:URL of t}
                                copy tabInfo to end of tabData
                            end repeat
                        end repeat
                        
                        return tabData
                    on error
                        return {}
                    end try
                else
                    return {}
                end if
            end tell
            """
        default:
            return nil
        }
        
        guard let result = executeListResult(script) as? [[String: String]] else { return nil }
        
        return result.compactMap { item in
            guard let title = item["title"],
                  let urlString = item["url"],
                  let url = URL(string: urlString) else {
                return nil
            }
            
            return (title: title, url: url)
        }
    }
    
    // MARK: - Private Methods
    
    /// Executes an AppleScript and returns the result as a string
    private func executeStringResult(_ script: String) -> String? {
        guard let scriptObject = NSAppleScript(source: script) else {
            logger.error("Failed to create AppleScript object")
            return nil
        }
        
        var error: NSDictionary?
        guard let output = scriptObject.executeAndReturnError(&error).stringValue, !output.isEmpty else {
            if let error = error {
                logger.error("AppleScript execution error: \(error)")
            }
            return nil
        }
        
        return output
    }
    
    /// Executes an AppleScript and returns the result as an object
    private func executeListResult(_ script: String) -> Any? {
        guard let scriptObject = NSAppleScript(source: script) else {
            logger.error("Failed to create AppleScript object")
            return nil
        }
        
        var error: NSDictionary?
        let output = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            logger.error("AppleScript execution error: \(error)")
            return nil
        }
        
        return output.toObject()
    }
} 