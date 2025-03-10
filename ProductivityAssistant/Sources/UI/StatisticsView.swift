import SwiftUI
import Combine

struct StatisticsView: View {
    @StateObject private var viewModel = StatisticsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Period selector
            HStack {
                Picker("Period", selection: $viewModel.selectedPeriodIndex) {
                    Text("Today").tag(0)
                    Text("Yesterday").tag(1)
                    Text("This Week").tag(2)
                    Text("Last Week").tag(3)
                    Text("This Month").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            if viewModel.isLoading {
                // Loading indicator
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading statistics...")
                        .font(.headline)
                        .padding()
                    Spacer()
                }
            } else if let stats = viewModel.statistics {
                // Statistics content
                ScrollView {
                    VStack(spacing: 20) {
                        // Summary cards
                        HStack(spacing: 16) {
                            // Productivity score
                            StatCard(
                                title: "Productivity Score",
                                value: "\(stats.productivityScore)",
                                icon: "chart.bar.fill",
                                color: .green
                            )
                            
                            // Active time
                            StatCard(
                                title: "Active Time",
                                value: Date.formatTimeInterval(stats.totalActiveTime),
                                icon: "clock.fill",
                                color: .blue
                            )
                            
                            // Longest streak
                            StatCard(
                                title: "Longest Streak",
                                value: Date.formatTimeInterval(stats.longestProductiveStreak),
                                icon: "flame.fill",
                                color: .orange
                            )
                        }
                        .padding(.horizontal)
                        
                        // Category breakdown
                        CategoryBreakdownView(categoryTimes: stats.categoryTimes)
                            .frame(height: 300)
                            .padding()
                        
                        // Top applications
                        if !stats.topApplications.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Top Applications")
                                    .font(.headline)
                                
                                ForEach(stats.topApplications.prefix(5), id: \.name) { app in
                                    TopItemRow(
                                        name: app.name,
                                        duration: Date.formatTimeInterval(app.duration),
                                        category: app.category,
                                        progress: calculateProgress(app.duration, total: stats.totalActiveTime)
                                    )
                                }
                            }
                            .padding()
                        }
                        
                        // Top websites
                        if !stats.topWebsites.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Top Websites")
                                    .font(.headline)
                                
                                ForEach(stats.topWebsites.prefix(5), id: \.host) { site in
                                    TopItemRow(
                                        name: site.host,
                                        duration: Date.formatTimeInterval(site.duration),
                                        category: site.category,
                                        progress: calculateProgress(site.duration, total: stats.totalActiveTime)
                                    )
                                }
                            }
                            .padding()
                        }
                        
                        // Usage patterns
                        if let patterns = viewModel.usagePatterns {
                            UsagePatternsView(patterns: patterns)
                                .padding()
                        }
                    }
                    .padding(.vertical)
                }
            } else {
                // Error or no data
                VStack {
                    Spacer()
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No statistics available")
                        .font(.headline)
                        .padding()
                    
                    if let error = viewModel.error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        Text("Start using the app to collect activity data")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Refresh") {
                        viewModel.loadStatistics()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            viewModel.loadStatistics()
        }
        .onChange(of: viewModel.selectedPeriodIndex) { _ in
            viewModel.loadStatistics()
        }
    }
    
    private func calculateProgress(_ value: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(value / total, 1.0)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
}

struct CategoryBreakdownView: View {
    let categoryTimes: [ActivityCategory: TimeInterval]
    
    private var totalTime: TimeInterval {
        categoryTimes.values.reduce(0, +)
    }
    
    private var segments: [PieSegment] {
        var segments: [PieSegment] = []
        var startAngle = 0.0
        
        for (category, time) in categoryTimes.sorted(by: { $0.value > $1.value }) {
            let percentage = totalTime > 0 ? time / totalTime : 0
            let endAngle = startAngle + (percentage * 360)
            
            segments.append(
                PieSegment(
                    startAngle: Angle(degrees: startAngle),
                    endAngle: Angle(degrees: endAngle),
                    color: category.color
                )
            )
            
            startAngle = endAngle
        }
        
        return segments
    }
    
    var body: some View {
        VStack {
            Text("Activity Breakdown")
                .font(.headline)
            
            GeometryReader { geometry in
                HStack {
                    // Pie chart
                    ZStack {
                        ForEach(segments.indices, id: \.self) { i in
                            PieSegmentShape(
                                startAngle: segments[i].startAngle,
                                endAngle: segments[i].endAngle
                            )
                            .fill(segments[i].color)
                        }
                        
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: geometry.size.width * 0.3, height: geometry.size.width * 0.3)
                        
                        VStack {
                            Text("\(Int(totalTime / 60))")
                                .font(.system(size: 20, weight: .bold))
                            Text("minutes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(categoryTimes.keys.sorted { categoryTimes[$0]! > categoryTimes[$1]! }), id: \.self) { category in
                            if let time = categoryTimes[category], time > 0 {
                                HStack {
                                    Circle()
                                        .fill(category.color)
                                        .frame(width: 12, height: 12)
                                    
                                    Text(category.displayName)
                                    
                                    Spacer()
                                    
                                    Text(Date.formatTimeInterval(time))
                                    
                                    Text("(\(Int((time / totalTime) * 100))%)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading)
                }
            }
        }
    }
    
    struct PieSegment {
        let startAngle: Angle
        let endAngle: Angle
        let color: Color
    }
    
    struct PieSegmentShape: Shape {
        let startAngle: Angle
        let endAngle: Angle
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: startAngle - .degrees(90), endAngle: endAngle - .degrees(90), clockwise: false)
            path.closeSubpath()
            
            return path
        }
    }
}

struct TopItemRow: View {
    let name: String
    let duration: String
    let category: ActivityCategory
    let progress: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name)
                    .lineLimit(1)
                Spacer()
                Text(duration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(category.color)
                        .frame(width: max(CGFloat(progress) * geometry.size.width, 4), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

struct UsagePatternsView: View {
    let patterns: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Patterns")
                .font(.headline)
            
            GroupBox {
                HStack {
                    PatternItem(
                        title: "Most Productive Hour",
                        value: formatHour(patterns["mostProductiveHour"] as? Int ?? 0),
                        icon: "sun.max.fill",
                        color: .green
                    )
                    
                    Divider()
                    
                    PatternItem(
                        title: "Most Distracting Hour",
                        value: formatHour(patterns["mostDistractingHour"] as? Int ?? 0),
                        icon: "moon.fill",
                        color: .red
                    )
                }
            }
            
            GroupBox {
                HStack {
                    PatternItem(
                        title: "Most Productive Day",
                        value: formatWeekday(patterns["mostProductiveDay"] as? Int ?? 0),
                        icon: "calendar",
                        color: .green
                    )
                    
                    Divider()
                    
                    PatternItem(
                        title: "Most Distracting Day",
                        value: formatWeekday(patterns["mostDistractingDay"] as? Int ?? 0),
                        icon: "calendar.badge.exclamationmark",
                        color: .red
                    )
                }
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        
        var components = DateComponents()
        components.hour = hour
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(hour)"
    }
    
    private func formatWeekday(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        
        var components = DateComponents()
        components.weekday = weekday
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "Unknown"
    }
}

struct PatternItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            
            Text(value)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

class StatisticsViewModel: ObservableObject {
    @Published var selectedPeriodIndex = 0
    @Published var statistics: ActivityStatistics?
    @Published var usagePatterns: [String: Any]?
    @Published var isLoading = false
    @Published var error: String?
    
    private var statisticsService: ActivityStatisticsService?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let repo = appDelegate.getActivityRepository() {
                statisticsService = DefaultActivityStatisticsService(activityRepository: repo)
            }
        }
    }
    
    func loadStatistics() {
        guard let service = statisticsService else {
            error = "Statistics service not available"
            return
        }
        
        let period = getCurrentPeriod()
        isLoading = true
        error = nil
        
        // Load statistics
        service.getStatistics(for: period)
            .zip(service.getUsagePatterns(for: period))
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let err) = completion {
                        self?.error = err.localizedDescription
                    }
                },
                receiveValue: { [weak self] stats, patterns in
                    self?.statistics = stats
                    self?.usagePatterns = patterns
                }
            )
            .store(in: &cancellables)
    }
    
    private func getCurrentPeriod() -> TimePeriod {
        let today = Date()
        
        switch selectedPeriodIndex {
        case 0:
            return .day(today)
        case 1:
            return .day(Calendar.current.date(byAdding: .day, value: -1, to: today)!)
        case 2:
            return .week(today)
        case 3:
            return .week(Calendar.current.date(byAdding: .weekOfYear, value: -1, to: today)!)
        case 4:
            return .month(today)
        default:
            return .day(today)
        }
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView()
    }
} 