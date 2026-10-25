import SwiftUI
import AppKit
import Charts

// MARK: - Analytics (app and website time, measured by ScreenUsageTracker)
public struct UsageAnalyticsView: View {
    @ObservedObject private var tracker = ScreenUsageTracker.shared
    @State private var range = "Today"
    private let ranges = ["Today", "Yesterday", "Last 7 Days"]

    private typealias Category = ScreenUsageTracker.Category
    private typealias DayUsage = ScreenUsageTracker.DayUsage

    private var accent: Color { SquircleTokens.accentColor(for: "usage") }
    private var isWeek: Bool { range == "Last 7 Days" }

    /// Days in the selected range, oldest first.
    private var selectedDays: [(date: Date, usage: DayUsage)] {
        let offsets = range == "Today" ? [0] : range == "Yesterday" ? [1] : Array((0..<7).reversed())
        return offsets.map { back in
            (Calendar.current.date(byAdding: .day, value: -back, to: Date())!, tracker.usage(daysBack: back))
        }
    }

    private var combined: DayUsage {
        selectedDays.map(\.usage).reduce(DayUsage()) { $0.merged(with: $1) }
    }

    public var body: some View {
        let usage = combined
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header

                JellyRadioPicker(items: ranges, selection: $range, label: "Time range")
                    .frame(maxWidth: .infinity)

                if usage.total < 1 {
                    Text(range == "Today"
                         ? "Nothing yet today. Keep Locken open while you use your Mac and your time shows up here."
                         : "No usage recorded for this period. Locken only counts time while it's open.")
                        .font(.appFont(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.l)
                        .luxuryObsidianCard(cornerRadius: 16)
                    websitesCard(usage)
                } else {
                    statTiles(usage)
                    categoriesCard(usage)
                    chartCard
                    // Apps and websites side by side as two equal-height tiles.
                    HStack(alignment: .top, spacing: Spacing.m) {
                        appsCard(usage)
                        websitesCard(usage)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .lockenPage()
        }
        .gradualBlurBottom()
    }

    // MARK: Sections

    private var header: some View {
        PageHeader(
            title: "Analytics",
            subtitle: "Time in apps and websites on this Mac. Apple doesn't share Screen Time with Mac apps, so Locken measures it itself while it's open."
        ) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tracker.isPaused ? Color.white.opacity(0.4) : SquircleTokens.mintAccent)
                    .frame(width: 7, height: 7)
                Text(tracker.isPaused ? "Paused while your Mac is idle or locked" : "Tracking now")
                    .font(.appFont(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func statTiles(_ usage: DayUsage) -> some View {
        let social = usage.seconds(in: .social)
        let share = Int((social / usage.total * 100).rounded())
        let topApp = usage.apps.max { $0.value.seconds < $1.value.seconds }?.value
        return HStack(spacing: Spacing.m) {
            statTile(
                title: "SCREEN TIME",
                value: Self.duration(usage.total),
                detail: isWeek ? "\(Self.duration(usage.total / 7)) daily average" : "Apps and websites"
            )
            statTile(
                title: "SOCIAL MEDIA",
                value: Self.duration(social),
                detail: "\(share)% of screen time",
                valueColor: Self.color(.social)
            )
            statTile(
                title: "MOST USED",
                value: topApp?.name ?? "—",
                detail: topApp.map { Self.duration($0.seconds) } ?? ""
            )
        }
    }

    private func statTile(title: String, value: String, detail: String, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(value)
                .font(.appFont(size: 24, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    private func categoriesCard(_ usage: DayUsage) -> some View {
        let categories = Category.allCases
            .map { ($0, usage.seconds(in: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("CATEGORIES")
            GeometryReader { geo in
                let spacing: CGFloat = 2
                let available = geo.size.width - spacing * CGFloat(max(categories.count - 1, 0))
                HStack(spacing: spacing) {
                    ForEach(categories, id: \.0) { category, seconds in
                        Rectangle()
                            .fill(Self.color(category))
                            .frame(width: max(2, available * seconds / usage.total))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(categories, id: \.0) { category, seconds in
                    HStack(spacing: 8) {
                        Circle().fill(Self.color(category)).frame(width: 8, height: 8)
                        Text(category.title)
                            .font(.appFont(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Text(Self.duration(seconds))
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    /// Hourly bars for a single day, daily bars for the week; social media is its own color in each bar.
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(isWeek ? "DAILY SCREEN TIME (HOURS)" : "BY HOUR (MINUTES)")
            Chart {
                if isWeek {
                    ForEach(selectedDays, id: \.date) { day in
                        let social = day.usage.seconds(in: .social)
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", social / 3600))
                            .foregroundStyle(by: .value("Type", "Social media"))
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", (day.usage.total - social) / 3600))
                            .foregroundStyle(by: .value("Type", "Everything else"))
                    }
                } else {
                    let usage = combined
                    ForEach(0..<24, id: \.self) { hour in
                        BarMark(x: .value("Hour", hour), y: .value("Minutes", usage.hourlySocial[hour] / 60))
                            .foregroundStyle(by: .value("Type", "Social media"))
                        BarMark(x: .value("Hour", hour), y: .value("Minutes", (usage.hourly[hour] - usage.hourlySocial[hour]) / 60))
                            .foregroundStyle(by: .value("Type", "Everything else"))
                    }
                }
            }
            .chartForegroundStyleScale(["Social media": Self.color(.social), "Everything else": accent.opacity(0.75)])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                if isWeek {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.appFont(size: 10))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                } else {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(Self.hourLabel(hour))
                            }
                        }
                        .font(.appFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.appFont(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .frame(height: 190)
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    private func appsCard(_ usage: DayUsage) -> some View {
        let apps = usage.apps
            .filter { tracker.isListable($0.key) }
            .sorted { $0.value.seconds > $1.value.seconds }
            .prefix(8)
        return VStack(alignment: .leading, spacing: 16) {
            sectionLabel("APPS")
            ForEach(Array(apps), id: \.key) { bundleID, app in
                let category = tracker.category(forApp: bundleID)
                HStack(spacing: 12) {
                    Image(nsImage: Self.icon(for: bundleID))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(category.title)
                            .font(.appFont(size: 11))
                            .foregroundColor(category == .social ? Self.color(.social) : .white.opacity(0.45))
                    }
                    Spacer()
                    Text(Self.duration(app.seconds))
                        .font(.appFont(size: 13))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    private func websitesCard(_ usage: DayUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("WEBSITES")
                Spacer()
                if tracker.tracksWebsites {
                    Button("Stop counting websites") { tracker.disableWebsiteTracking() }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            if !tracker.tracksWebsites {
                Text("Count social media in your browser")
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Locken reads only the address of the tab in front in Safari, Chrome, Comet, Arc, Brave or Edge, and keeps just the site name on this Mac. macOS asks you once for each browser.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button { tracker.enableWebsiteTracking() } label: {
                    Text("Count Websites")
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            } else {
                let sites = usage.sites.sorted { $0.value > $1.value }.prefix(6)
                if sites.isEmpty {
                    Text("No websites yet. Browse in Safari, Chrome, Comet, Arc, Brave or Edge and they show up here.")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(sites), id: \.key) { domain, seconds in
                            let category = ScreenUsageTracker.category(forDomain: domain) ?? .web
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Self.color(category))
                                    .frame(width: 7, height: 7)
                                Text(domain)
                                    .font(.appFont(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(Self.duration(seconds))
                                    .font(.appFont(size: 13))
                                    .monospacedDigit()
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(domain), \(category.title), \(Self.duration(seconds))")
                        }
                    }
                }

                if !tracker.blockedBrowsers.isEmpty {
                    HStack(spacing: 10) {
                        Text("Locken can't see tabs in \(tracker.blockedBrowsers.sorted().joined(separator: ", ")). Turn it on under Privacy & Security › Automation.")
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Open Automation Settings")
                                .font(.appFont(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .borderGlowButton(accent: accent, isProminent: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appFont(size: 10, weight: .bold))
            .tracking(1.0)
            .foregroundColor(.white.opacity(0.5))
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "\(Int(seconds))s" }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        default: return hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
        }
    }

    static func color(_ category: ScreenUsageTracker.Category) -> Color {
        switch category {
        case .social: return Color(red: 0.96, green: 0.45, blue: 0.62)
        case .entertainment: return SquircleTokens.smokedAmber
        case .productivity: return SquircleTokens.mintAccent
        case .development: return Color(red: 56/255.0, green: 189/255.0, blue: 248/255.0)
        case .web: return SquircleTokens.royalPlum
        case .other: return SquircleTokens.titaniumPlatinum
        }
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage()
        iconCache[bundleID] = icon
        return icon
    }
}

extension ScreenUsageTracker.DayUsage {
    /// Sums two days, for multi-day ranges.
    func merged(with other: Self) -> Self {
        var result = self
        for (id, app) in other.apps {
            result.apps[id, default: .init(name: app.name, seconds: 0)].seconds += app.seconds
        }
        result.sites.merge(other.sites, uniquingKeysWith: +)
        result.categories.merge(other.categories, uniquingKeysWith: +)
        result.hourly = zip(hourly, other.hourly).map(+)
        result.hourlySocial = zip(hourlySocial, other.hourlySocial).map(+)
        return result
    }
}
