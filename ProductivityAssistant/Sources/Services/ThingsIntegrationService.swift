import Foundation
import Combine
import os.log

/// Protocol for interacting with Things 3 task manager
protocol ThingsIntegrationService {
    /// Checks if Things 3 is installed on the system
    var isThingsInstalled: Bool { get }
    
    /// Fetches all tasks from Things 3
    func fetchTasks() -> AnyPublisher<[ThingsTask], Error>
    
    /// Fetches all tasks (including completed) from Things 3 for synchronization
    func fetchAllTasks() -> AnyPublisher<[ThingsTask], Error>
    
    /// Fetches tasks filtered by project
    func fetchTasksByProject(project: String) -> AnyPublisher<[ThingsTask], Error>
    
    /// Fetches tasks filtered by tag
    func fetchTasksByTag(tag: String) -> AnyPublisher<[ThingsTask], Error>
    
    /// Fetches tasks due today
    func fetchTasksDueToday() -> AnyPublisher<[ThingsTask], Error>
    
    /// Marks a task as complete by its ID
    func markTaskComplete(id: String) -> AnyPublisher<Bool, Error>
    
    /// Creates a new task in Things 3
    func createTask(title: String, notes: String?, dueDate: Date?, 
                   project: String?, tags: [String]?) -> AnyPublisher<ThingsTask?, Error>
    
    /// Fetches all projects from Things 3
    func fetchProjects() -> AnyPublisher<[ThingsProject], Error>
    
    /// Fetches all areas from Things 3
    func fetchAreas() -> AnyPublisher<[ThingsArea], Error>
    
    /// Fetches all tags from Things 3
    func fetchTags() -> AnyPublisher<[ThingsTag], Error>
}

/// Implementation of ThingsIntegrationService using AppleScript
final class AppleScriptThingsIntegration: ThingsIntegrationService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "ThingsIntegration")
    private let dateFormatter: DateFormatter
    private let thingsInstallCheck: Bool
    
    var isThingsInstalled: Bool {
        return thingsInstallCheck
    }
    
    // MARK: - Initialization
    
    init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Check if Things 3 is installed
        let fileManager = FileManager.default
        let thingsAppPath = "/Applications/Things3.app"
        self.thingsInstallCheck = fileManager.fileExists(atPath: thingsAppPath)
        
        if !thingsInstallCheck {
            logger.warning("Things 3 is not installed at the expected location")
        } else {
            logger.info("Things 3 was found at: \(thingsAppPath)")
        }
    }
    
    // MARK: - Public Methods
    
    func fetchTasks() -> AnyPublisher<[ThingsTask], Error> {
        return executeThingsScript(fetchTasksScript())
            .map { self.parseTasksFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchAllTasks() -> AnyPublisher<[ThingsTask], Error> {
        return executeThingsScript(fetchAllTasksScript())
            .map { self.parseTasksFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchTasksByProject(project: String) -> AnyPublisher<[ThingsTask], Error> {
        return executeThingsScript(fetchTasksByProjectScript(project: project))
            .map { self.parseTasksFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchTasksByTag(tag: String) -> AnyPublisher<[ThingsTask], Error> {
        return executeThingsScript(fetchTasksByTagScript(tag: tag))
            .map { self.parseTasksFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchTasksDueToday() -> AnyPublisher<[ThingsTask], Error> {
        return executeThingsScript(fetchTasksDueTodayScript())
            .map { self.parseTasksFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func markTaskComplete(id: String) -> AnyPublisher<Bool, Error> {
        return executeThingsScript(markTaskCompleteScript(id: id))
            .map { _ in true }
            .eraseToAnyPublisher()
    }
    
    func createTask(title: String, notes: String?, dueDate: Date?, project: String?, tags: [String]?) -> AnyPublisher<ThingsTask?, Error> {
        return executeThingsScript(createTaskScript(
            title: title,
            notes: notes,
            dueDate: dueDate,
            project: project,
            tags: tags
        ))
        .map { result -> ThingsTask? in
            guard let taskDict = result.first as? [String: Any],
                  let id = taskDict["id"] as? String else {
                return nil
            }
            
            // Simplified approach - in a real app, we would parse the full task
            let createdTask = ThingsTask(
                id: id,
                title: title,
                notes: notes,
                dueDate: dueDate,
                tags: tags ?? [],
                project: project,
                completed: false,
                checklist: nil,
                creationDate: Date(),
                modificationDate: Date()
            )
            
            return createdTask
        }
        .eraseToAnyPublisher()
    }
    
    func fetchProjects() -> AnyPublisher<[ThingsProject], Error> {
        return executeThingsScript(fetchProjectsScript())
            .map { self.parseProjectsFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchAreas() -> AnyPublisher<[ThingsArea], Error> {
        return executeThingsScript(fetchAreasScript())
            .map { self.parseAreasFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    func fetchTags() -> AnyPublisher<[ThingsTag], Error> {
        return executeThingsScript(fetchTagsScript())
            .map { self.parseTagsFromScriptResult($0) }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func executeThingsScript<T>(_ script: String) -> AnyPublisher<T, Error> {
        return Future<T, Error> { promise in
            guard self.isThingsInstalled else {
                promise(.failure(ThingsIntegrationError.notInstalled))
                return
            }
            
            guard let scriptObject = NSAppleScript(source: script) else {
                self.logger.error("Failed to create AppleScript object")
                promise(.failure(ThingsIntegrationError.scriptExecutionFailed))
                return
            }
            
            var error: NSDictionary?
            let result = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                self.logger.error("AppleScript execution error: \(error)")
                
                // Check for permission error
                if let errorNumber = error["NSAppleScriptErrorNumber"] as? Int, errorNumber == -1743 {
                    promise(.failure(ThingsIntegrationError.permissionDenied))
                } else {
                    promise(.failure(ThingsIntegrationError.scriptExecutionFailed))
                }
                return
            }
            
            guard let resultArray = result.toObject() as? T else {
                self.logger.error("Failed to parse AppleScript result")
                promise(.failure(ThingsIntegrationError.parseError))
                return
            }
            
            promise(.success(resultArray))
        }
        .eraseToAnyPublisher()
    }
    
    // Parser methods
    private func parseTasksFromScriptResult(_ result: [[String: Any]]) -> [ThingsTask] {
        return result.compactMap { dict -> ThingsTask? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String else {
                return nil
            }
            
            let notes = dict["notes"] as? String
            
            // Parse due date if available
            var dueDate: Date? = nil
            if let dueDateString = dict["dueDate"] as? String, !dueDateString.isEmpty {
                dueDate = dateFormatter.date(from: dueDateString)
            }
            
            // Parse tags
            let tags = dict["tags"] as? [String] ?? []
            
            // Parse project
            let project = dict["project"] as? String
            
            // Parse completed status
            let completed = dict["completed"] as? Bool ?? false
            
            // Parse checklist items
            var checklist: [ThingsChecklistItem]? = nil
            if let checklistArray = dict["checklist"] as? [[String: Any]], !checklistArray.isEmpty {
                checklist = checklistArray.compactMap { item -> ThingsChecklistItem? in
                    guard let id = item["id"] as? String,
                          let title = item["title"] as? String,
                          let completed = item["completed"] as? Bool else {
                        return nil
                    }
                    
                    return ThingsChecklistItem(id: id, title: title, completed: completed)
                }
            }
            
            // Parse dates
            let creationDate = (dict["creationDate"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
            let modificationDate = (dict["modificationDate"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
            
            return ThingsTask(
                id: id,
                title: title,
                notes: notes,
                dueDate: dueDate,
                tags: tags,
                project: project,
                completed: completed,
                checklist: checklist,
                creationDate: creationDate,
                modificationDate: modificationDate
            )
        }
    }
    
    private func parseProjectsFromScriptResult(_ result: [[String: Any]]) -> [ThingsProject] {
        return result.compactMap { dict -> ThingsProject? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String else {
                return nil
            }
            
            let notes = dict["notes"] as? String
            let tags = dict["tags"] as? [String] ?? []
            let area = dict["area"] as? String
            let taskCount = dict["taskCount"] as? Int ?? 0
            let completedTaskCount = dict["completedTaskCount"] as? Int ?? 0
            
            return ThingsProject(
                id: id,
                title: title,
                notes: notes,
                tags: tags,
                area: area,
                taskCount: taskCount,
                completedTaskCount: completedTaskCount
            )
        }
    }
    
    private func parseAreasFromScriptResult(_ result: [[String: Any]]) -> [ThingsArea] {
        return result.compactMap { dict -> ThingsArea? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String else {
                return nil
            }
            
            let projectCount = dict["projectCount"] as? Int ?? 0
            
            return ThingsArea(id: id, title: title, projectCount: projectCount)
        }
    }
    
    private func parseTagsFromScriptResult(_ result: [[String: Any]]) -> [ThingsTag] {
        return result.compactMap { dict -> ThingsTag? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String else {
                return nil
            }
            
            let taskCount = dict["taskCount"] as? Int ?? 0
            
            return ThingsTag(id: id, title: title, taskCount: taskCount)
        }
    }
    
    // AppleScript generators
    private func fetchTasksScript() -> String {
        return """
        tell application "Things3"
            set taskList to {}
            
            try
                repeat with t in to dos
                    set taskProps to {id:id of t, title:name of t, notes:notes of t, completed:completed of t}
                    
                    -- Handle due date
                    if due date of t is not missing value then
                        set taskProps to taskProps & {dueDate:(due date of t as string)}
                    else
                        set taskProps to taskProps & {dueDate:""}
                    end if
                    
                    -- Handle tags
                    set taskTags to {}
                    repeat with aTag in tags of t
                        set end of taskTags to name of aTag
                    end repeat
                    set taskProps to taskProps & {tags:taskTags}
                    
                    -- Handle project
                    if project of t is not missing value then
                        set taskProps to taskProps & {project:name of project of t}
                    else
                        set taskProps to taskProps & {project:""}
                    end if
                    
                    -- Handle creation/modification dates
                    set taskProps to taskProps & {creationDate:(creation date of t as string)}
                    set taskProps to taskProps & {modificationDate:(modification date of t as string)}
                    
                    copy taskProps to end of taskList
                end repeat
                
                return taskList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchAllTasksScript() -> String {
        return """
        tell application "Things3"
            set taskList to {}
            
            try
                -- Get all to dos including completed
                set allAreas to areas
                set allProjects to projects
                set allToDos to every to do
                
                repeat with t in allToDos
                    set taskProps to {id:id of t, title:name of t, notes:notes of t, completed:completed of t}
                    
                    -- Handle due date
                    if due date of t is not missing value then
                        set taskProps to taskProps & {dueDate:(due date of t as string)}
                    else
                        set taskProps to taskProps & {dueDate:""}
                    end if
                    
                    -- Handle tags
                    set taskTags to {}
                    repeat with aTag in tags of t
                        set end of taskTags to name of aTag
                    end repeat
                    set taskProps to taskProps & {tags:taskTags}
                    
                    -- Handle project
                    if project of t is not missing value then
                        set taskProps to taskProps & {project:name of project of t}
                    else
                        set taskProps to taskProps & {project:""}
                    end if
                    
                    -- Handle creation/modification dates
                    set taskProps to taskProps & {creationDate:(creation date of t as string)}
                    set taskProps to taskProps & {modificationDate:(modification date of t as string)}
                    
                    copy taskProps to end of taskList
                end repeat
                
                return taskList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchTasksByProjectScript(project: String) -> String {
        return """
        tell application "Things3"
            set taskList to {}
            
            try
                set projectObj to first item of (get projects whose name is "\(escapeAppleScriptString(project))")
                
                repeat with t in to dos of projectObj
                    set taskProps to {id:id of t, title:name of t, notes:notes of t, completed:completed of t}
                    
                    -- Handle due date
                    if due date of t is not missing value then
                        set taskProps to taskProps & {dueDate:(due date of t as string)}
                    else
                        set taskProps to taskProps & {dueDate:""}
                    end if
                    
                    -- Handle tags
                    set taskTags to {}
                    repeat with aTag in tags of t
                        set end of taskTags to name of aTag
                    end repeat
                    set taskProps to taskProps & {tags:taskTags}
                    
                    -- Handle project
                    set taskProps to taskProps & {project:name of projectObj}
                    
                    -- Handle creation/modification dates
                    set taskProps to taskProps & {creationDate:(creation date of t as string)}
                    set taskProps to taskProps & {modificationDate:(modification date of t as string)}
                    
                    copy taskProps to end of taskList
                end repeat
                
                return taskList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchTasksByTagScript(tag: String) -> String {
        return """
        tell application "Things3"
            set taskList to {}
            
            try
                set tagObj to first item of (get tags whose name is "\(escapeAppleScriptString(tag))")
                
                repeat with t in to dos of tagObj
                    set taskProps to {id:id of t, title:name of t, notes:notes of t, completed:completed of t}
                    
                    -- Handle due date
                    if due date of t is not missing value then
                        set taskProps to taskProps & {dueDate:(due date of t as string)}
                    else
                        set taskProps to taskProps & {dueDate:""}
                    end if
                    
                    -- Handle tags
                    set taskTags to {}
                    repeat with aTag in tags of t
                        set end of taskTags to name of aTag
                    end repeat
                    set taskProps to taskProps & {tags:taskTags}
                    
                    -- Handle project
                    if project of t is not missing value then
                        set taskProps to taskProps & {project:name of project of t}
                    else
                        set taskProps to taskProps & {project:""}
                    end if
                    
                    -- Handle creation/modification dates
                    set taskProps to taskProps & {creationDate:(creation date of t as string)}
                    set taskProps to taskProps & {modificationDate:(modification date of t as string)}
                    
                    copy taskProps to end of taskList
                end repeat
                
                return taskList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchTasksDueTodayScript() -> String {
        return """
        tell application "Things3"
            set taskList to {}
            
            try
                repeat with t in to dos of list "Today"
                    if completed of t is false then
                        set taskProps to {id:id of t, title:name of t, notes:notes of t, completed:completed of t}
                        
                        -- Handle due date
                        if due date of t is not missing value then
                            set taskProps to taskProps & {dueDate:(due date of t as string)}
                        else
                            set taskProps to taskProps & {dueDate:""}
                        end if
                        
                        -- Handle tags
                        set taskTags to {}
                        repeat with aTag in tags of t
                            set end of taskTags to name of aTag
                        end repeat
                        set taskProps to taskProps & {tags:taskTags}
                        
                        -- Handle project
                        if project of t is not missing value then
                            set taskProps to taskProps & {project:name of project of t}
                        else
                            set taskProps to taskProps & {project:""}
                        end if
                        
                        -- Handle creation/modification dates
                        set taskProps to taskProps & {creationDate:(creation date of t as string)}
                        set taskProps to taskProps & {modificationDate:(modification date of t as string)}
                        
                        copy taskProps to end of taskList
                    end if
                end repeat
                
                return taskList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func markTaskCompleteScript(id: String) -> String {
        return """
        tell application "Things3"
            try
                set targetTask to first item of (get to dos whose id is "\(escapeAppleScriptString(id))")
                set completed of targetTask to true
                return {success:true}
            on error
                return {success:false}
            end try
        end tell
        """
    }
    
    private func createTaskScript(title: String, notes: String?, dueDate: Date?, project: String?, tags: [String]?) -> String {
        var script = """
        tell application "Things3"
            try
                set newToDo to make new to do with properties {name:"\(escapeAppleScriptString(title))\"
        """
        
        if let notes = notes, !notes.isEmpty {
            script += ", notes:\"\(escapeAppleScriptString(notes))\""
        }
        
        if let dueDate = dueDate {
            let dueDateString = dateFormatter.string(from: dueDate)
            script += ", due date:date \"\(dueDateString)\""
        }
        
        script += "}\n"
        
        if let project = project, !project.isEmpty {
            script += """
                    try
                        set projectObj to first item of (get projects whose name is "\(escapeAppleScriptString(project))")
                        set project of newToDo to projectObj
                    end try
            """
        }
        
        if let tags = tags, !tags.isEmpty {
            script += "\n"
            for tag in tags {
                script += """
                        try
                            set tagObj to first item of (get tags whose name is "\(escapeAppleScriptString(tag))")
                            make new tag with properties {name:"\(escapeAppleScriptString(tag))"} at end of tags of newToDo
                        end try
                """
            }
        }
        
        script += """
                return {id:id of newToDo}
            on error
                return {}
            end try
        end tell
        """
        
        return script
    }
    
    private func fetchProjectsScript() -> String {
        return """
        tell application "Things3"
            set projectList to {}
            
            try
                repeat with p in projects
                    set projectProps to {id:id of p, title:name of p, notes:notes of p}
                    
                    -- Handle area
                    if area of p is not missing value then
                        set projectProps to projectProps & {area:name of area of p}
                    else
                        set projectProps to projectProps & {area:""}
                    end if
                    
                    -- Handle tags
                    set projectTags to {}
                    repeat with aTag in tags of p
                        set end of projectTags to name of aTag
                    end repeat
                    set projectProps to projectProps & {tags:projectTags}
                    
                    -- Count tasks
                    set taskCount to count of (get to dos of p whose completed is false)
                    set completedTaskCount to count of (get to dos of p whose completed is true)
                    set projectProps to projectProps & {taskCount:taskCount, completedTaskCount:completedTaskCount}
                    
                    copy projectProps to end of projectList
                end repeat
                
                return projectList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchAreasScript() -> String {
        return """
        tell application "Things3"
            set areaList to {}
            
            try
                repeat with a in areas
                    set areaProps to {id:id of a, title:name of a}
                    
                    -- Count projects
                    set projectCount to count of (get projects of a)
                    set areaProps to areaProps & {projectCount:projectCount}
                    
                    copy areaProps to end of areaList
                end repeat
                
                return areaList
            on error
                return {}
            end try
        end tell
        """
    }
    
    private func fetchTagsScript() -> String {
        return """
        tell application "Things3"
            set tagList to {}
            
            try
                repeat with t in tags
                    set tagProps to {id:id of t, title:name of t}
                    
                    -- Count tasks
                    set taskCount to count of (get to dos of t)
                    set tagProps to tagProps & {taskCount:taskCount}
                    
                    copy tagProps to end of tagList
                end repeat
                
                return tagList
            on error
                return {}
            end try
        end tell
        """
    }
    
    /// Escapes special characters in strings for AppleScript
    private func escapeAppleScriptString(_ string: String) -> String {
        return string.replacingOccurrences(of: "\"", with: "\\\"")
    }
} 