import Foundation
import AppKit
import UserNotifications
import os.log

/// Handles permission requests for the application
final class PermissionsHandler {
    // MARK: - Properties
    
    static let shared = PermissionsHandler()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Permissions")
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Requests all required permissions for the app
    func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        // Request notification permissions first
        requestNotificationPermissions { [weak self] notificationGranted in
            guard let self = self else { return }
            
            self.logger.info("Notification permissions \(notificationGranted ? "granted" : "denied")")
            
            // Then request accessibility permissions
            DispatchQueue.main.async {
                self.showAccessibilityPermissionAlert { accessibilityResponse in
                    self.logger.info("Accessibility permission dialog response: \(accessibilityResponse)")
                    
                    let allPermissionsGranted = notificationGranted && self.checkAccessibilityPermissions()
                    completion(allPermissionsGranted)
                }
            }
        }
    }
    
    /// Checks if the app has accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Shows the accessibility permission dialog
    func showAccessibilityPermissionAlert(completion: @escaping (Bool) -> Void) {
        // Skip if we already have permissions
        if checkAccessibilityPermissions() {
            logger.info("Accessibility permissions already granted")
            completion(true)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Productivity Assistant needs accessibility permissions to track your active applications. Please click 'Open Preferences' and add Productivity Assistant to the list of allowed apps."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Not Now")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open the Security & Privacy preferences
            let prefPaneURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
            let prefRef = NSWorkspace.shared.urlForApplication(toOpen: prefPaneURL)
            
            if let prefRef = prefRef {
                logger.info("Opening Security & Privacy preferences")
                NSWorkspace.shared.openFile(
                    "/System/Library/PreferencePanes/Security.prefPane",
                    withApplication: prefRef.lastPathComponent
                )
                
                // Prompt for accessibility permissions
                let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
                let options = [checkOptPrompt: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
                
                // Check again after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self = self else { return }
                    let granted = self.checkAccessibilityPermissions()
                    self.logger.info("Accessibility permissions check after delay: \(granted ? "granted" : "denied")")
                    completion(granted)
                }
            } else {
                logger.error("Failed to find Security preferences application")
                completion(false)
            }
        } else {
            logger.info("User chose not to open accessibility permissions")
            completion(false)
        }
    }
    
    /// Requests notification permissions
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
            if let error = error {
                self.logger.error("Error requesting notification permissions: \(error.localizedDescription)")
            }
            
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

/// Extensions to UNAuthorizationStatus for easier permission handling
extension UNAuthorizationStatus {
    /// Returns true if the notification authorization status is authorized
    var isAuthorized: Bool {
        return self == .authorized || self == .provisional
    }
} 