import Foundation

extension Date {
    /// Returns the start of the day (midnight) for this date
    var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    /// Returns the end of the day (23:59:59) for this date
    var endOfDay: Date {
        let components = DateComponents(day: 1, second: -1)
        return Calendar.current.date(byAdding: components, to: startOfDay)!
    }
    
    /// Returns the start of the week for this date
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)!
    }
    
    /// Returns the end of the week for this date
    var endOfWeek: Date {
        let calendar = Calendar.current
        let components = DateComponents(day: 7, second: -1)
        return calendar.date(byAdding: components, to: startOfWeek)!
    }
    
    /// Returns the start of the month for this date
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)!
    }
    
    /// Returns the end of the month for this date
    var endOfMonth: Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return calendar.date(byAdding: components, to: startOfMonth)!
    }
    
    /// Returns a formatted string for the date
    func formattedString(format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    /// Returns a relative description of the date (e.g., "Today", "Yesterday")
    var relativeDescription: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else if calendar.isDateInTomorrow(self) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }
    
    /// Returns a time string (e.g., "3:30 PM")
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Returns a time interval description (e.g., "2h 30m")
    static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Adds a specified number of days to the date and returns a new date
    func adding(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
    
    /// Returns true if the date is between the specified start and end dates
    func isBetween(_ start: Date, and end: Date) -> Bool {
        return (start...end).contains(self)
    }
} 