import Foundation
import Combine
import os.log

/// Protocol defining the operations for categorizing activities
protocol ActivityCategorizationService {
    /// Categorizes an activity based on application and content
    func categorizeActivity(applicationName: String, windowTitle: String?, url: URL?) -> ActivityCategory
    
    /// Adds a custom categorization rule
    func addCategorizationRule(applicationName: String, urlPattern: String?, windowTitlePattern: String?, category: ActivityCategory) throws
    
    /// Updates an existing categorization rule
    func updateCategorizationRule(ruleId: String, applicationName: String, urlPattern: String?, windowTitlePattern: String?, category: ActivityCategory) throws
    
    /// Deletes a categorization rule
    func deleteCategorizationRule(ruleId: String) throws
    
    /// Gets all categorization rules
    func getAllRules() throws -> [CategoryRule]
    
    /// Gets categorization rules for a specific application
    func getRulesForApplication(applicationName: String) throws -> [CategoryRule]
    
    /// Gets suggestions for categorizing an uncategorized activity
    func getSuggestions(for activity: ActivityRecord) -> [ActivityCategory]
    
    /// Publisher for categorization rule changes
    var rulesChangedPublisher: AnyPublisher<Void, Never> { get }
}

/// Implementation of the ActivityCategorizationService
final class DefaultActivityCategorizationService: ActivityCategorizationService {
    // MARK: - Properties
    
    private let categoryRepository: CategoryRepositoryProtocol
    private let browserIntegration: BrowserIntegrationService
    private let rulesChangedSubject = PassthroughSubject<Void, Never>()
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Categorization")
    
    // Cached rules for performance
    private var cachedRules: [CategoryRule] = []
    private var lastRuleUpdateTime = Date(timeIntervalSince1970: 0)
    
    var rulesChangedPublisher: AnyPublisher<Void, Never> {
        return rulesChangedSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(categoryRepository: CategoryRepositoryProtocol, browserIntegration: BrowserIntegrationService) {
        self.categoryRepository = categoryRepository
        self.browserIntegration = browserIntegration
        
        // Initial cache load
        refreshRuleCache()
        
        // Listen for repository changes
        categoryRepository.categoryChangesPublisher
            .sink { [weak self] _ in
                self?.refreshRuleCache()
                self?.rulesChangedSubject.send()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    
    func categorizeActivity(applicationName: String, windowTitle: String?, url: URL?) -> ActivityCategory {
        logger.debug("Categorizing activity: \(applicationName)")
        
        // Check if this is a browser with a URL
        if let url = url, browserIntegration.isSupportedBrowser(applicationName) {
            return categorizeURL(url, browserName: applicationName)
        }
        
        // Check custom rules first
        if let category = applyCachedRules(applicationName: applicationName, windowTitle: windowTitle, url: url) {
            return category
        }
        
        // Use the built-in categorization as a fallback
        return ActivityCategory.categorize(applicationName: applicationName, url: url, windowTitle: windowTitle)
    }
    
    func addCategorizationRule(applicationName: String, urlPattern: String?, windowTitlePattern: String?, category: ActivityCategory) throws {
        let categoryId = ActivityCategoryType.from(category).rawValue
        
        let rule = CategoryRule(
            applicationName: applicationName,
            urlPattern: urlPattern,
            windowTitlePattern: windowTitlePattern,
            categoryId: categoryId
        )
        
        try categoryRepository.saveCategoryRule(rule)
        logger.info("Added new categorization rule for \(applicationName) as \(category.rawValue)")
        
        // Update cache
        refreshRuleCache()
        rulesChangedSubject.send()
    }
    
    func updateCategorizationRule(ruleId: String, applicationName: String, urlPattern: String?, windowTitlePattern: String?, category: ActivityCategory) throws {
        let categoryId = ActivityCategoryType.from(category).rawValue
        
        let rule = CategoryRule(
            id: ruleId,
            applicationName: applicationName,
            urlPattern: urlPattern,
            windowTitlePattern: windowTitlePattern,
            categoryId: categoryId
        )
        
        try categoryRepository.updateCategoryRule(rule)
        logger.info("Updated categorization rule \(ruleId) for \(applicationName)")
        
        // Update cache
        refreshRuleCache()
        rulesChangedSubject.send()
    }
    
    func deleteCategorizationRule(ruleId: String) throws {
        try categoryRepository.deleteCategoryRule(id: ruleId)
        logger.info("Deleted categorization rule \(ruleId)")
        
        // Update cache
        refreshRuleCache()
        rulesChangedSubject.send()
    }
    
    func getAllRules() throws -> [CategoryRule] {
        return try categoryRepository.getAllCategoryRules()
    }
    
    func getRulesForApplication(applicationName: String) throws -> [CategoryRule] {
        return try categoryRepository.getCategoryRulesByApplication(applicationName: applicationName)
    }
    
    func getSuggestions(for activity: ActivityRecord) -> [ActivityCategory] {
        var suggestions: [ActivityCategory] = []
        
        // First, add the current category as a suggestion
        suggestions.append(activity.category)
        
        // Add other categories that aren't the current one
        for category in ActivityCategory.allCases {
            if category != activity.category && category != .custom {
                suggestions.append(category)
            }
        }
        
        // If this is a browser URL, we could add more sophisticated suggestions here
        // based on keywords in the URL or page title
        if activity.applicationType == .browserTab, let url = activity.url, let host = url.host {
            // Check for educational domains
            if host.contains("edu") || host.contains("learn") || host.contains("course") {
                // Move productive to the top if it's not already there
                if !suggestions.contains(where: { $0 == .productive }) {
                    suggestions.insert(.productive, at: 0)
                }
            }
            
            // Check for entertainment domains
            if host.contains("game") || host.contains("play") || host.contains("video") || host.contains("stream") {
                // Move distracting to the top if it's not already there
                if !suggestions.contains(where: { $0 == .distracting }) {
                    suggestions.insert(.distracting, at: 0)
                }
            }
        }
        
        return suggestions
    }
    
    // MARK: - Private Methods
    
    private func categorizeURL(_ url: URL, browserName: String) -> ActivityCategory {
        // Use browser integration service to categorize the URL
        return browserIntegration.categorizeURL(url)
    }
    
    private func applyCachedRules(applicationName: String, windowTitle: String?, url: URL?) -> ActivityCategory? {
        // Refresh the cache if it's outdated or empty
        if cachedRules.isEmpty || Date().timeIntervalSince(lastRuleUpdateTime) > 60 {
            refreshRuleCache()
        }
        
        // Extract host from URL if available
        let host = url?.host?.lowercased()
        
        // First, look for exact application name matches
        let appRules = cachedRules.filter { $0.applicationName == applicationName }
        
        for rule in appRules {
            // Check for URL pattern match
            if let urlPattern = rule.urlPattern?.lowercased(), 
               let host = host, 
               host.contains(urlPattern) {
                if let categoryRecord = getCategoryFromId(rule.categoryId) {
                    logger.debug("Activity matched URL rule: \(applicationName) - \(host) - \(categoryRecord.type.rawValue)")
                    return categoryRecord.type.toActivityCategory
                }
            }
            
            // Check for window title match
            if let titlePattern = rule.windowTitlePattern?.lowercased(), 
               let title = windowTitle?.lowercased(),
               title.contains(titlePattern) {
                if let categoryRecord = getCategoryFromId(rule.categoryId) {
                    logger.debug("Activity matched window title rule: \(applicationName) - \(title) - \(categoryRecord.type.rawValue)")
                    return categoryRecord.type.toActivityCategory
                }
            }
            
            // Application-level match with no specific pattern
            if rule.urlPattern == nil && rule.windowTitlePattern == nil {
                if let categoryRecord = getCategoryFromId(rule.categoryId) {
                    logger.debug("Activity matched app-level rule: \(applicationName) - \(categoryRecord.type.rawValue)")
                    return categoryRecord.type.toActivityCategory
                }
            }
        }
        
        // Next, look for partial application name matches
        let partialAppRules = cachedRules.filter { 
            guard let ruleName = $0.applicationName else { return false }
            return applicationName.contains(ruleName) || ruleName.contains(applicationName)
        }
        
        for rule in partialAppRules {
            // Same checks as above
            if let urlPattern = rule.urlPattern?.lowercased(), 
               let host = host, 
               host.contains(urlPattern) {
                if let categoryRecord = getCategoryFromId(rule.categoryId) {
                    return categoryRecord.type.toActivityCategory
                }
            }
            
            if let titlePattern = rule.windowTitlePattern?.lowercased(), 
               let title = windowTitle?.lowercased(),
               title.contains(titlePattern) {
                if let categoryRecord = getCategoryFromId(rule.categoryId) {
                    return categoryRecord.type.toActivityCategory
                }
            }
        }
        
        // No matches found
        return nil
    }
    
    private func getCategoryFromId(_ categoryId: String) -> ActivityCategoryRecord? {
        do {
            return try categoryRepository.getCategoryById(id: categoryId)
        } catch {
            logger.error("Failed to get category by ID \(categoryId): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func refreshRuleCache() {
        do {
            cachedRules = try categoryRepository.getAllCategoryRules()
            lastRuleUpdateTime = Date()
            logger.debug("Refreshed rule cache, loaded \(cachedRules.count) rules")
        } catch {
            logger.error("Failed to refresh rule cache: \(error.localizedDescription)")
        }
    }
} 