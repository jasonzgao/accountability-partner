import Foundation
import GRDB
import Combine

/// Protocol defining the operations for managing activity categories
protocol CategoryRepositoryProtocol {
    /// Saves a category to the database
    func saveCategory(_ category: ActivityCategoryRecord) throws
    
    /// Updates an existing category
    func updateCategory(_ category: ActivityCategoryRecord) throws
    
    /// Deletes a category from the database
    func deleteCategory(id: String) throws
    
    /// Retrieves a category by its ID
    func getCategoryById(id: String) throws -> ActivityCategoryRecord?
    
    /// Retrieves all categories
    func getAllCategories() throws -> [ActivityCategoryRecord]
    
    /// Retrieves categories by type
    func getCategoriesByType(_ type: ActivityCategoryType) throws -> [ActivityCategoryRecord]
    
    /// Saves a category rule to the database
    func saveCategoryRule(_ rule: CategoryRule) throws
    
    /// Updates an existing category rule
    func updateCategoryRule(_ rule: CategoryRule) throws
    
    /// Deletes a category rule from the database
    func deleteCategoryRule(id: String) throws
    
    /// Retrieves a category rule by its ID
    func getCategoryRuleById(id: String) throws -> CategoryRule?
    
    /// Retrieves all category rules
    func getAllCategoryRules() throws -> [CategoryRule]
    
    /// Retrieves category rules for a specific category
    func getCategoryRulesByCategory(categoryId: String) throws -> [CategoryRule]
    
    /// Retrieves category rules for a specific application
    func getCategoryRulesByApplication(applicationName: String) throws -> [CategoryRule]
    
    /// Publisher for category changes
    var categoryChangesPublisher: AnyPublisher<Void, Error> { get }
}

/// Implementation of the CategoryRepository using GRDB
final class CategoryRepository: CategoryRepositoryProtocol {
    // MARK: - Properties
    
    private let databaseManager: DatabaseManager
    private let categoryChangesSubject = PassthroughSubject<Void, Error>()
    
    var categoryChangesPublisher: AnyPublisher<Void, Error> {
        return categoryChangesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Category Methods
    
    func saveCategory(_ category: ActivityCategoryRecord) throws {
        try databaseManager.write { db in
            try category.save(db)
            categoryChangesSubject.send()
        }
    }
    
    func updateCategory(_ category: ActivityCategoryRecord) throws {
        try databaseManager.write { db in
            try category.update(db)
            categoryChangesSubject.send()
        }
    }
    
    func deleteCategory(id: String) throws {
        try databaseManager.write { db in
            _ = try ActivityCategoryRecord.filter(Column("id") == id).deleteAll(db)
            categoryChangesSubject.send()
        }
    }
    
    func getCategoryById(id: String) throws -> ActivityCategoryRecord? {
        try databaseManager.read { db in
            try ActivityCategoryRecord.filter(Column("id") == id).fetchOne(db)
        }
    }
    
    func getAllCategories() throws -> [ActivityCategoryRecord] {
        try databaseManager.read { db in
            try ActivityCategoryRecord.order(Column("name")).fetchAll(db)
        }
    }
    
    func getCategoriesByType(_ type: ActivityCategoryType) throws -> [ActivityCategoryRecord] {
        try databaseManager.read { db in
            try ActivityCategoryRecord
                .filter(Column("type") == type.rawValue)
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    // MARK: - Category Rule Methods
    
    func saveCategoryRule(_ rule: CategoryRule) throws {
        try databaseManager.write { db in
            try rule.save(db)
            categoryChangesSubject.send()
        }
    }
    
    func updateCategoryRule(_ rule: CategoryRule) throws {
        try databaseManager.write { db in
            try rule.update(db)
            categoryChangesSubject.send()
        }
    }
    
    func deleteCategoryRule(id: String) throws {
        try databaseManager.write { db in
            _ = try CategoryRule.filter(Column("id") == id).deleteAll(db)
            categoryChangesSubject.send()
        }
    }
    
    func getCategoryRuleById(id: String) throws -> CategoryRule? {
        try databaseManager.read { db in
            try CategoryRule.filter(Column("id") == id).fetchOne(db)
        }
    }
    
    func getAllCategoryRules() throws -> [CategoryRule] {
        try databaseManager.read { db in
            try CategoryRule.fetchAll(db)
        }
    }
    
    func getCategoryRulesByCategory(categoryId: String) throws -> [CategoryRule] {
        try databaseManager.read { db in
            try CategoryRule
                .filter(Column("category_id") == categoryId)
                .fetchAll(db)
        }
    }
    
    func getCategoryRulesByApplication(applicationName: String) throws -> [CategoryRule] {
        try databaseManager.read { db in
            try CategoryRule
                .filter(Column("application_name") == applicationName)
                .fetchAll(db)
        }
    }
}

/// Record type for persisted activity categories
struct ActivityCategoryRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var type: ActivityCategoryType
    var color: String?
    
    static var databaseTableName: String {
        return "activity_categories"
    }
}

/// Category rule for categorizing applications and websites
struct CategoryRule: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var applicationName: String?
    var urlPattern: String?
    var windowTitlePattern: String?
    var categoryId: String
    
    static var databaseTableName: String {
        return "category_rules"
    }
    
    enum Columns {
        static let id = Column("id")
        static let applicationName = Column("application_name")
        static let urlPattern = Column("url_pattern")
        static let windowTitlePattern = Column("window_title_pattern")
        static let categoryId = Column("category_id")
    }
    
    // GRDB column mapping
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    
    init(id: String = UUID().uuidString,
         applicationName: String? = nil,
         urlPattern: String? = nil,
         windowTitlePattern: String? = nil,
         categoryId: String) {
        self.id = id
        self.applicationName = applicationName
        self.urlPattern = urlPattern
        self.windowTitlePattern = windowTitlePattern
        self.categoryId = categoryId
    }
} 