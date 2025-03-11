import Foundation
import Combine
import os.log

/// Protocol for interacting with Notion Calendar
protocol NotionCalendarService {
    /// Checks if the service is authenticated with Notion
    var isAuthenticated: Bool { get }
    
    /// Authenticates with Notion using an integration token
    func authenticate(token: String) -> AnyPublisher<Bool, Error>
    
    /// Fetches events within a date range
    func fetchEvents(from: Date, to: Date) -> AnyPublisher<[NotionEvent], Error>
    
    /// Fetches upcoming events with a limit
    func fetchUpcomingEvents(limit: Int) -> AnyPublisher<[NotionEvent], Error>
    
    /// Gets the current ongoing event if any
    func getCurrentEvent() -> AnyPublisher<NotionEvent?, Error>
    
    /// Gets the next upcoming event if any
    func getNextEvent() -> AnyPublisher<NotionEvent?, Error>
    
    /// Lists available calendar databases
    func listDatabases() -> AnyPublisher<[NotionDatabase], Error>
    
    /// Sets the active database for calendar events
    func setActiveDatabase(id: String) -> AnyPublisher<Bool, Error>
    
    /// Gets the active database ID
    var activeDatabaseId: String? { get }
    
    /// Clears authentication and cached data
    func logout() -> AnyPublisher<Bool, Error>
    
    /// Fetches events for a specific database for a number of days
    func fetchEvents(for databaseId: String, startDate: Date, days: Int) -> AnyPublisher<[NotionEvent], Error>
    
    /// Gets a list of selected databases for synchronization
    func fetchSelectedDatabases() -> AnyPublisher<[NotionDatabase], Error>
}

/// Implementation of NotionCalendarService using the Notion API
final class NotionAPICalendarService: NotionCalendarService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "NotionCalendar")
    private let baseURL = URL(string: "https://api.notion.com/v1")!
    private let userDefaults: UserDefaults
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let authManager: AuthenticationManagerProtocol
    
    private var authState: NotionAuthState?
    private var eventCache: [String: [NotionEvent]] = [:]
    private var databaseCache: [NotionDatabase] = []
    private var lastCacheUpdate: Date?
    private var cacheTimeout: TimeInterval = 15 * 60 // 15 minutes
    
    private enum UserDefaultsKeys {
        static let activeDatabaseId = "notion_active_database_id"
    }
    
    private enum KeychainKeys {
        static let service = "com.productivityassistant.notion"
        static let tokenAccount = "integration_token"
    }
    
    var isAuthenticated: Bool {
        return authState?.isValid ?? false
    }
    
    var activeDatabaseId: String? {
        return userDefaults.string(forKey: UserDefaultsKeys.activeDatabaseId)
    }
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard, authManager: AuthenticationManagerProtocol? = nil) {
        self.userDefaults = userDefaults
        
        // Configure URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        
        // Configure JSON coding
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        // Get authentication manager from app delegate if not provided
        if let authManager = authManager {
            self.authManager = authManager
        } else if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            self.authManager = appDelegate.getAuthenticationManager()
        } else {
            // Fallback to a new instance if needed
            self.authManager = KeychainAuthenticationManager()
        }
        
        // Load saved auth state
        loadAuthState()
    }
    
    // MARK: - Public Methods
    
    func authenticate(token: String) -> AnyPublisher<Bool, Error> {
        // Make a request to verify the token and get user info
        return verifyToken(token)
            .flatMap { [weak self] userInfo -> AnyPublisher<Bool, Error> in
                guard let self = self else {
                    return Fail(error: NotionIntegrationError.unknown).eraseToAnyPublisher()
                }
                
                // Create a proper auth state with user info
                let authState = NotionAuthState(
                    accessToken: token,
                    workspaceId: userInfo["workspace_id"] as? String,
                    workspaceName: userInfo["workspace_name"] as? String,
                    workspaceIcon: userInfo["workspace_icon"] as? String,
                    userId: userInfo["user_id"] as? String,
                    botId: userInfo["bot_id"] as? String,
                    expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30) // 30 days
                )
                
                // Save the auth state
                self.authState = authState
                
                // Store the token securely in the keychain
                return self.authManager.storeCredential(token, for: KeychainKeys.service, account: KeychainKeys.tokenAccount)
            }
            .eraseToAnyPublisher()
    }
    
    func fetchEvents(from startDate: Date, to endDate: Date) -> AnyPublisher<[NotionEvent], Error> {
        guard isAuthenticated, let databaseId = activeDatabaseId else {
            return Fail(error: NotionIntegrationError.notAuthenticated).eraseToAnyPublisher()
        }
        
        // Check cache first
        let cacheKey = "\(databaseId)_\(startDate.timeIntervalSince1970)_\(endDate.timeIntervalSince1970)"
        if let cachedEvents = eventCache[cacheKey], 
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return Just(cachedEvents)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Build the query for the database
        let query: [String: Any] = [
            "filter": [
                "and": [
                    [
                        "property": "Date",
                        "date": [
                            "on_or_after": formatDateForNotion(startDate)
                        ]
                    ],
                    [
                        "property": "Date",
                        "date": [
                            "on_or_before": formatDateForNotion(endDate)
                        ]
                    ]
                ]
            ],
            "sorts": [
                [
                    "property": "Date",
                    "direction": "ascending"
                ]
            ]
        ]
        
        return queryDatabase(databaseId: databaseId, query: query)
            .map { [weak self] results -> [NotionEvent] in
                let events = self?.parseEventsFromResults(results, databaseId: databaseId) ?? []
                
                // Cache the results
                self?.eventCache[cacheKey] = events
                self?.lastCacheUpdate = Date()
                
                return events
            }
            .eraseToAnyPublisher()
    }
    
    func fetchUpcomingEvents(limit: Int) -> AnyPublisher<[NotionEvent], Error> {
        guard isAuthenticated, let databaseId = activeDatabaseId else {
            return Fail(error: NotionIntegrationError.notAuthenticated).eraseToAnyPublisher()
        }
        
        // Check cache first
        let cacheKey = "\(databaseId)_upcoming_\(limit)"
        if let cachedEvents = eventCache[cacheKey], 
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return Just(cachedEvents)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Build the query for the database
        let query: [String: Any] = [
            "filter": [
                "property": "Date",
                "date": [
                    "on_or_after": formatDateForNotion(Date())
                ]
            ],
            "sorts": [
                [
                    "property": "Date",
                    "direction": "ascending"
                ]
            ],
            "page_size": limit
        ]
        
        return queryDatabase(databaseId: databaseId, query: query)
            .map { [weak self] results -> [NotionEvent] in
                let events = self?.parseEventsFromResults(results, databaseId: databaseId) ?? []
                
                // Cache the results
                self?.eventCache[cacheKey] = events
                self?.lastCacheUpdate = Date()
                
                return events
            }
            .eraseToAnyPublisher()
    }
    
    func getCurrentEvent() -> AnyPublisher<NotionEvent?, Error> {
        let now = Date()
        
        return fetchEvents(from: now.addingTimeInterval(-60 * 60), to: now.addingTimeInterval(60 * 60))
            .map { events -> NotionEvent? in
                return events.first { event in
                    event.isCurrent
                }
            }
            .eraseToAnyPublisher()
    }
    
    func getNextEvent() -> AnyPublisher<NotionEvent?, Error> {
        return fetchUpcomingEvents(limit: 1)
            .map { events -> NotionEvent? in
                return events.first
            }
            .eraseToAnyPublisher()
    }
    
    func listDatabases() -> AnyPublisher<[NotionDatabase], Error> {
        guard isAuthenticated else {
            return Fail(error: NotionIntegrationError.notAuthenticated).eraseToAnyPublisher()
        }
        
        // Check cache first
        if !databaseCache.isEmpty, 
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return Just(databaseCache)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("search")
        
        // Build the search query for databases
        let query: [String: Any] = [
            "filter": [
                "value": "database",
                "property": "object"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(authState!.accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: query)
        } catch {
            return Fail(error: NotionIntegrationError.parseError).eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response -> [NotionDatabase] in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NotionIntegrationError.networkError("Invalid response")
                }
                
                // Check for API errors
                if httpResponse.statusCode == 401 {
                    throw NotionIntegrationError.invalidToken
                } else if httpResponse.statusCode == 429 {
                    throw NotionIntegrationError.rateLimitExceeded
                } else if httpResponse.statusCode != 200 {
                    throw NotionIntegrationError.apiError(code: httpResponse.statusCode, message: "API error")
                }
                
                // Parse the response
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    throw NotionIntegrationError.parseError
                }
                
                // Parse databases
                let databases = self?.parseDatabasesFromResults(results) ?? []
                
                // Cache the results
                self?.databaseCache = databases
                self?.lastCacheUpdate = Date()
                
                return databases
            }
            .eraseToAnyPublisher()
    }
    
    func setActiveDatabase(id: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NotionIntegrationError.unknown))
                return
            }
            
            // Verify the database exists
            self.listDatabases()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { databases in
                        if databases.contains(where: { $0.id == id }) {
                            // Save the active database ID
                            self.userDefaults.set(id, forKey: UserDefaultsKeys.activeDatabaseId)
                            promise(.success(true))
                        } else {
                            promise(.failure(NotionIntegrationError.databaseNotFound))
                        }
                    }
                )
        }
        .eraseToAnyPublisher()
    }
    
    func logout() -> AnyPublisher<Bool, Error> {
        return authManager.deleteCredential(for: KeychainKeys.service, account: KeychainKeys.tokenAccount)
            .map { [weak self] success -> Bool in
                guard let self = self else { return false }
                
                // Clear auth state
                self.authState = nil
                
                // Clear active database
                self.userDefaults.removeObject(forKey: UserDefaultsKeys.activeDatabaseId)
                
                // Clear caches
                self.eventCache = [:]
                self.databaseCache = []
                self.lastCacheUpdate = nil
                
                return success
            }
            .eraseToAnyPublisher()
    }
    
    func fetchEvents(for databaseId: String, startDate: Date, days: Int) -> AnyPublisher<[NotionEvent], Error> {
        guard isAuthenticated, let databaseId = activeDatabaseId else {
            return Fail(error: NotionIntegrationError.notAuthenticated).eraseToAnyPublisher()
        }
        
        // Check cache first
        let cacheKey = "\(databaseId)_\(startDate.timeIntervalSince1970)_\(startDate.timeIntervalSince1970 + Double(days * 86400))"
        if let cachedEvents = eventCache[cacheKey], 
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return Just(cachedEvents)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Build the query for the database
        let query: [String: Any] = [
            "filter": [
                "and": [
                    [
                        "property": "Date",
                        "date": [
                            "on_or_after": formatDateForNotion(startDate)
                        ]
                    ],
                    [
                        "property": "Date",
                        "date": [
                            "on_or_before": formatDateForNotion(startDate.addingTimeInterval(Double(days * 86400)))
                        ]
                    ]
                ]
            ],
            "sorts": [
                [
                    "property": "Date",
                    "direction": "ascending"
                ]
            ]
        ]
        
        return queryDatabase(databaseId: databaseId, query: query)
            .map { [weak self] results -> [NotionEvent] in
                let events = self?.parseEventsFromResults(results, databaseId: databaseId) ?? []
                
                // Cache the results
                self?.eventCache[cacheKey] = events
                self?.lastCacheUpdate = Date()
                
                return events
            }
            .eraseToAnyPublisher()
    }
    
    func fetchSelectedDatabases() -> AnyPublisher<[NotionDatabase], Error> {
        // Implementation needed
        return Fail(error: NotionIntegrationError.notImplemented).eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func loadAuthState() {
        // Try to load token from keychain
        authManager.getCredential(for: KeychainKeys.service, account: KeychainKeys.tokenAccount)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Failed to load token from keychain: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] token in
                    guard let self = self, let token = token else { return }
                    
                    // Create auth state with token
                    self.authState = NotionAuthState(
                        accessToken: token,
                        workspaceId: nil,
                        workspaceName: nil,
                        workspaceIcon: nil,
                        userId: nil,
                        botId: nil,
                        expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30) // 30 days
                    )
                    
                    self.logger.info("Loaded Notion token from keychain")
                }
            )
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func verifyToken(_ token: String) -> AnyPublisher<[String: Any], Error> {
        let url = baseURL.appendingPathComponent("users/me")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response -> [String: Any] in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NotionIntegrationError.networkError("Invalid response")
                }
                
                // Check for API errors
                if httpResponse.statusCode == 401 {
                    throw NotionIntegrationError.invalidToken
                } else if httpResponse.statusCode == 429 {
                    throw NotionIntegrationError.rateLimitExceeded
                } else if httpResponse.statusCode != 200 {
                    throw NotionIntegrationError.apiError(code: httpResponse.statusCode, message: "API error")
                }
                
                // Parse the response
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NotionIntegrationError.parseError
                }
                
                return json
            }
            .eraseToAnyPublisher()
    }
    
    private func queryDatabase(databaseId: String, query: [String: Any]) -> AnyPublisher<[[String: Any]], Error> {
        guard let authState = authState else {
            return Fail(error: NotionIntegrationError.notAuthenticated).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("databases/\(databaseId)/query")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(authState.accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: query)
        } catch {
            return Fail(error: NotionIntegrationError.parseError).eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response -> [[String: Any]] in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NotionIntegrationError.networkError("Invalid response")
                }
                
                // Check for API errors
                if httpResponse.statusCode == 401 {
                    throw NotionIntegrationError.invalidToken
                } else if httpResponse.statusCode == 429 {
                    throw NotionIntegrationError.rateLimitExceeded
                } else if httpResponse.statusCode != 200 {
                    throw NotionIntegrationError.apiError(code: httpResponse.statusCode, message: "API error")
                }
                
                // Parse the response
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    throw NotionIntegrationError.parseError
                }
                
                return results
            }
            .eraseToAnyPublisher()
    }
    
    private func parseEventsFromResults(_ results: [[String: Any]], databaseId: String) -> [NotionEvent] {
        var events: [NotionEvent] = []
        
        for result in results {
            guard let id = result["id"] as? String,
                  let properties = result["properties"] as? [String: Any],
                  let createdTime = result["created_time"] as? String,
                  let lastEditedTime = result["last_edited_time"] as? String else {
                continue
            }
            
            // Extract title
            guard let titleProperty = properties["Name"] as? [String: Any],
                  let titleArray = titleProperty["title"] as? [[String: Any]],
                  let firstTitle = titleArray.first,
                  let plainText = firstTitle["plain_text"] as? String else {
                continue
            }
            
            // Extract date
            guard let dateProperty = properties["Date"] as? [String: Any],
                  let dateObject = dateProperty["date"] as? [String: Any],
                  let startString = dateObject["start"] as? String else {
                continue
            }
            
            let endString = dateObject["end"] as? String
            
            // Parse dates
            let dateFormatter = ISO8601DateFormatter()
            guard let startTime = dateFormatter.date(from: startString) else {
                continue
            }
            
            let endTime = endString.flatMap { dateFormatter.date(from: $0) } ?? startTime.addingTimeInterval(3600) // Default to 1 hour
            
            // Extract location
            var location: String? = nil
            if let locationProperty = properties["Location"] as? [String: Any],
               let richText = locationProperty["rich_text"] as? [[String: Any]],
               let firstText = richText.first,
               let plainLocation = firstText["plain_text"] as? String {
                location = plainLocation
            }
            
            // Extract notes
            var notes: String? = nil
            if let notesProperty = properties["Notes"] as? [String: Any],
               let richText = notesProperty["rich_text"] as? [[String: Any]],
               let firstText = richText.first,
               let plainNotes = firstText["plain_text"] as? String {
                notes = plainNotes
            }
            
            // Extract URL
            var url: URL? = nil
            if let urlProperty = properties["URL"] as? [String: Any],
               let urlString = urlProperty["url"] as? String {
                url = URL(string: urlString)
            }
            
            // Extract attendees
            var attendees: [String] = []
            if let attendeesProperty = properties["Attendees"] as? [String: Any],
               let peopleArray = attendeesProperty["people"] as? [[String: Any]] {
                for person in peopleArray {
                    if let personObject = person["person"] as? [String: Any],
                       let name = personObject["name"] as? String {
                        attendees.append(name)
                    }
                }
            }
            
            // Create the event
            let event = NotionEvent(
                id: id,
                title: plainText,
                startTime: startTime,
                endTime: endTime,
                location: location,
                url: url,
                notes: notes,
                attendees: attendees.isEmpty ? nil : attendees,
                databaseId: databaseId,
                pageId: id,
                createdTime: dateFormatter.date(from: createdTime) ?? Date(),
                lastEditedTime: dateFormatter.date(from: lastEditedTime) ?? Date()
            )
            
            events.append(event)
        }
        
        return events
    }
    
    private func parseDatabasesFromResults(_ results: [[String: Any]]) -> [NotionDatabase] {
        var databases: [NotionDatabase] = []
        
        for result in results {
            guard let id = result["id"] as? String,
                  let title = result["title"] as? [[String: Any]],
                  let firstTitle = title.first,
                  let plainText = firstTitle["plain_text"] as? String else {
                continue
            }
            
            // Create the database
            let database = NotionDatabase(
                id: id,
                title: plainText,
                lastSyncedTime: nil,
                eventCount: 0
            )
            
            databases.append(database)
        }
        
        return databases
    }
    
    private func formatDateForNotion(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
} 