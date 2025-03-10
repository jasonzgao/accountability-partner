import Foundation
import GRDB

/// Represents a single activity record tracking the user's application or website usage
struct ActivityRecord: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    // MARK: - Properties
    
    /// Unique identifier for the activity record
    var id: UUID
    
    /// When the activity started
    var startTime: Date
    
    /// When the activity ended (nil if ongoing)
    var endTime: Date?
    
    /// Type of application (desktop, browser, system)
    var applicationType: ApplicationType
    
    /// Name of the application
    var applicationName: String
    
    /// Window title of the application
    var windowTitle: String?
    
    /// URL if the activity is a website
    var url: URL?
    
    /// Activity category (productive, neutral, distracting)
    var category: ActivityCategory
    
    // MARK: - Database Configuration
    
    /// Table name in the database
    static var databaseTableName: String {
        return "activity_records"
    }
    
    /// Column mapping strategy
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    
    // MARK: - Computed Properties
    
    /// Duration of the activity in seconds
    var durationInSeconds: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Formatted duration string (e.g. "2h 30m")
    var formattedDuration: String {
        guard let duration = durationInSeconds else { return "Ongoing" }
        
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Description of the activity (app name or website title)
    var description: String {
        if applicationType == .browserTab, let url = url {
            return url.host ?? applicationName
        } else {
            return applicationName
        }
    }
    
    // MARK: - Initialization
    
    /// Create a new activity record
    init(id: UUID = UUID(),
         startTime: Date = Date(),
         endTime: Date? = nil,
         applicationType: ApplicationType,
         applicationName: String,
         windowTitle: String? = nil,
         url: URL? = nil,
         category: ActivityCategory) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.applicationType = applicationType
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.url = url
        self.category = category
    }
    
    // MARK: - Codable Support
    
    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, applicationType, applicationName, windowTitle, url, category
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode standard properties
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        applicationType = try container.decode(ApplicationType.self, forKey: .applicationType)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        
        // Decode URL string to URL
        if let urlString = try container.decodeIfPresent(String.self, forKey: .url) {
            url = URL(string: urlString)
        } else {
            url = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode standard properties
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encode(applicationType, forKey: .applicationType)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encode(category, forKey: .category)
        
        // Encode URL to string
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
    }
    
    // MARK: - GRDB Support
    
    /// For encoding to the database
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["start_time"] = startTime
        container["end_time"] = endTime
        container["application_type"] = applicationType.rawValue
        container["application_name"] = applicationName
        container["window_title"] = windowTitle
        container["url"] = url?.absoluteString
        container["category"] = category.rawValue
    }
    
    /// For decoding from the database
    init(row: Row) throws {
        id = try UUID(uuidString: row["id"])!
        startTime = try row["start_time"]
        endTime = try row["end_time"]
        
        let appTypeString: String = try row["application_type"]
        applicationType = ApplicationType(rawValue: appTypeString)!
        
        applicationName = try row["application_name"]
        windowTitle = try row["window_title"]
        
        if let urlString: String = try row["url"] {
            url = URL(string: urlString)
        } else {
            url = nil
        }
        
        let categoryString: String = try row["category"]
        category = ActivityCategory(rawValue: categoryString)!
    }
} 