import Foundation
import Combine
import os.log

/// Protocol defining the operations for browser integration
protocol BrowserIntegrationService {
    /// Gets the current URL from the active browser tab
    func getCurrentURL(for browserName: String) -> URL?
    
    /// Gets all open tabs for a browser
    func getAllTabs(for browserName: String) -> [(title: String, url: URL)]?
    
    /// Checks if the application is a supported browser
    func isSupportedBrowser(_ appName: String) -> Bool
    
    /// Gets the list of supported browsers
    var supportedBrowsers: [String] { get }
    
    /// Categorizes a URL based on predefined and user-defined rules
    func categorizeURL(_ url: URL) -> ActivityCategory
    
    /// Publisher for browser tab changes (if available)
    var tabChangePublisher: AnyPublisher<(browser: String, url: URL), Never> { get }
}

/// Implementation of BrowserIntegrationService
final class MacOSBrowserIntegration: BrowserIntegrationService {
    // MARK: - Properties
    
    private let appleScriptManager = AppleScriptManager.shared
    private let categoryRepository: CategoryRepositoryProtocol
    private let tabChangeSubject = PassthroughSubject<(browser: String, url: URL), Never>()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "BrowserIntegration")
    
    // List of known browsers
    let supportedBrowsers = [
        "Safari",
        "Google Chrome",
        "Firefox",
        "Microsoft Edge",
        "Opera",
        "Brave Browser"
    ]
    
    // List of known productive domains
    private let productiveDomains = [
        "github.com",
        "stackoverflow.com",
        "docs.swift.org",
        "developer.apple.com",
        "medium.com",
        "dev.to",
        "notion.so",
        "trello.com",
        "asana.com",
        "jira.com",
        "confluence.com",
        "gitlab.com",
        "bitbucket.org"
    ]
    
    // List of known distracting domains
    private let distractingDomains = [
        "netflix.com",
        "youtube.com",
        "twitter.com",
        "facebook.com",
        "instagram.com",
        "tiktok.com",
        "reddit.com",
        "twitch.tv",
        "hulu.com",
        "disney.plus.com",
        "snapchat.com",
        "pinterest.com"
    ]
    
    var tabChangePublisher: AnyPublisher<(browser: String, url: URL), Never> {
        return tabChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(categoryRepository: CategoryRepositoryProtocol) {
        self.categoryRepository = categoryRepository
    }
    
    // MARK: - Public Methods
    
    func getCurrentURL(for browserName: String) -> URL? {
        let url = appleScriptManager.getBrowserURL(browserName: browserName)
        
        if let url = url {
            logger.debug("Got URL from \(browserName): \(url.absoluteString)")
        } else {
            logger.debug("Failed to get URL from \(browserName)")
        }
        
        return url
    }
    
    func getAllTabs(for browserName: String) -> [(title: String, url: URL)]? {
        let tabs = appleScriptManager.getAllBrowserTabs(browserName: browserName)
        
        if let tabs = tabs {
            logger.debug("Got \(tabs.count) tabs from \(browserName)")
        } else {
            logger.debug("Failed to get tabs from \(browserName)")
        }
        
        return tabs
    }
    
    func isSupportedBrowser(_ appName: String) -> Bool {
        return supportedBrowsers.contains { appName.contains($0) }
    }
    
    func categorizeURL(_ url: URL) -> ActivityCategory {
        // Get the host from the URL
        guard let host = url.host?.lowercased() else {
            return .neutral
        }
        
        // Check custom rules from database first
        if let rules = try? categoryRepository.getAllCategoryRules() {
            for rule in rules {
                if let urlPattern = rule.urlPattern, host.contains(urlPattern.lowercased()) {
                    if let categoryRecord = try? categoryRepository.getCategoryById(id: rule.categoryId) {
                        logger.debug("URL \(host) matched custom rule for category \(categoryRecord.type.rawValue)")
                        return categoryRecord.type.toActivityCategory
                    }
                }
            }
        }
        
        // Check built-in productive domains
        for domain in productiveDomains {
            if host.contains(domain) {
                logger.debug("URL \(host) matched built-in productive domain \(domain)")
                return .productive
            }
        }
        
        // Check built-in distracting domains
        for domain in distractingDomains {
            if host.contains(domain) {
                logger.debug("URL \(host) matched built-in distracting domain \(domain)")
                return .distracting
            }
        }
        
        // Analyze URL components for additional categorization
        if host.contains("mail.") || host.contains("calendar.") || 
           host.contains("docs.") || host.contains("drive.") {
            logger.debug("URL \(host) matched productivity-related service")
            return .productive
        }
        
        if host.contains("news.") || host.contains("video.") || 
           host.contains("play.") || host.contains("game.") {
            logger.debug("URL \(host) matched entertainment-related service")
            return .distracting
        }
        
        // Default to neutral for unknown URLs
        logger.debug("URL \(host) is uncategorized, defaulting to neutral")
        return .neutral
    }
} 