import AppKit
import Charts
import SwiftUI

// MARK: - Pages and periods

/// The console's pages, grouped in the sidebar.
enum AdminPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case analytics = "Analytics"
    case users = "Users"
    case integrations = "Integrations"
    case usage = "AI & Usage"
    case health = "System Health"
    case events = "Events & Logs"
    case security = "Security"
    case settings = "Admin Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .analytics: return "chart.xyaxis.line"
        case .users: return "person.2"
        case .integrations: return "point.3.connected.trianglepath.dotted"
        case .usage: return "gauge.with.dots.needle.33percent"
        case .health: return "waveform.path.ecg"
        case .events: return "list.bullet.rectangle"
        case .security: return "lock.shield"
        case .settings: return "slider.horizontal.3"
        }
    }

    var summary: String {
        switch self {
        case .overview: return "What needs attention right now"
        case .analytics: return "Growth, engagement, retention and feedback over time"
        case .users: return "Every account, with filters and a detail view"
        case .integrations: return "Sign-in methods, email codes, the update server and the database"
        case .usage: return "What Locken uses of its free plans, and where AI runs"
        case .health: return "Update server, database and which builds people run"
        case .events: return "Sign-ups, sign-ins, confirmations and data changes, newest first"
        case .security: return "Access checks, two-factor, sessions and admin accounts"
        case .settings: return "Admins, refresh, export, and how the numbers are worked out"
        }
    }

    /// Sidebar groups: a short label and its pages. The settings page sits on its own at the bottom.
    static let groups: [(label: String, pages: [AdminPage])] = [
        ("Monitor", [.overview, .analytics]),
        ("People", [.users]),
        ("Platform", [.integrations, .usage, .health]),
        ("Records", [.events, .security]),
    ]
}

/// The time window every chart and comparison uses.
enum AdminRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90
    var id: Int { rawValue }
    var label: String { "\(rawValue)d" }
    var phrase: String {
        switch self {
        case .week: return "last 7 days"
        case .month: return "last 30 days"
        case .quarter: return "last 90 days"
        }
    }
    var previousPhrase: String {
        switch self {
        case .week: return "the 7 days before"
        case .month: return "the 30 days before"
        case .quarter: return "the 90 days before"
        }
    }
    var axisStride: Int {
        switch self {
        case .week: return 1
        case .month: return 5
        case .quarter: return 14
        }
    }
}

// MARK: - Theme

/// The console's own look: graphite with amber and teal, not Locken's purple.
enum AdminTheme {
    static let bg = Color(red: 0.05, green: 0.055, blue: 0.065)
    static let sidebar = Color(red: 0.06, green: 0.065, blue: 0.078)
    static let panel = Color(red: 0.085, green: 0.09, blue: 0.11)
    static let raised = Color.white.opacity(0.04)
    static let amber = Color(red: 0.95, green: 0.71, blue: 0.27)
    static let teal = Color(red: 0.24, green: 0.84, blue: 0.77)
    static let red = Color(red: 0.95, green: 0.45, blue: 0.45)
    static let green = Color(red: 0.42, green: 0.85, blue: 0.52)
    static let line = Color.white.opacity(0.12)
    static let faint = Color.white.opacity(0.07)
    static let muted = Color.white.opacity(0.58)
    static let text = Color.white.opacity(0.9)

    static func color(for level: AdminData.Alert.Level) -> Color {
        switch level {
        case .critical: return red
        case .warning: return amber
        case .info: return teal
        }
    }
}

// MARK: - The console

/// The owner's operations workspace. Replaces the whole window in admin mode; "Back to Locken" returns to the app.
struct AdminConsoleView: View {
    @ObservedObject private var admin = AdminManager.shared
    @ObservedObject private var state = TestAppStateManager.shared
    @State private var page: AdminPage = .overview
    @AppStorage("admin.range") private var rangeValue = AdminRange.month.rawValue
    @AppStorage("admin.autoRefresh") private var autoRefresh = true

    private var range: AdminRange { AdminRange(rawValue: rangeValue) ?? .month }
    private var data: AdminData { AdminData(admin.overview) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(AdminTheme.faint).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(AdminTheme.faint).frame(height: 1)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = admin.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.appFont(size: 12, weight: .medium))
                                .foregroundColor(AdminTheme.amber)
                        }
                        if admin.overview.isEmpty {
                            loadingState
                        } else {
                            content
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1240, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                // The console runs to the window's edge, so the band has square corners.
                .gradualBlurBottom(cornerRadius: 0)
            }
        }
        .background(AdminTheme.bg.ignoresSafeArea())
        .task { if admin.overview.isEmpty { await admin.refresh() } }
        // Live: refreshes every second while the console is open and Locken is the front app (turn off in
        // Admin Settings). Paused in the background so it doesn't call the server when no one is looking.
        .task(id: autoRefresh) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                guard NSApp.isActive else { continue }
                await admin.refresh(silent: true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let open: (AdminPage) -> Void = { target in page = target }
        switch page {
        case .overview: AdminOverviewPage(data: data, range: range, open: open)
        case .analytics: AdminAnalyticsPage(data: data, range: range)
        case .users: AdminUsersPage(data: data)
        case .integrations: AdminIntegrationsPage(data: data)
        case .usage: AdminUsagePage(data: data, range: range)
        case .health: AdminHealthPage(data: data)
        case .events: AdminEventsPage(data: data, range: range)
        case .security: AdminSecurityPage(data: data)
        case .settings: AdminSettingsPage(data: data, autoRefresh: $autoRefresh, range: Binding(
            get: { range }, set: { rangeValue = $0.rawValue }))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AdminTheme.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Locken").font(.appFont(size: 15, weight: .bold)).foregroundColor(.white)
                    Text("Control room").font(.appFont(size: 11, weight: .medium)).foregroundColor(AdminTheme.amber.opacity(0.9))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AdminPage.groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.label)
                                .font(.appFont(size: 11, weight: .semibold))
                                .foregroundColor(AdminTheme.muted)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)
                            ForEach(group.pages) { item in sidebarItem(item) }
                        }
                    }
                }
            }

            Spacer(minLength: 12)
            sidebarItem(.settings)
            Button {
                state.selectedTab = "dashboard"
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Back to Locken").font(.appFont(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AdminTheme.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(width: 236)
        .background(AdminTheme.sidebar)
    }

    private func sidebarItem(_ item: AdminPage) -> some View {
        let selected = page == item
        let badge: (count: Int, color: Color)? = {
            guard !admin.overview.isEmpty else { return nil }
            switch item {
            case .overview:
                let urgent = data.alerts.filter { $0.level != .info }
                return urgent.isEmpty ? nil : (urgent.count, AdminTheme.color(for: urgent[0].level))
            case .users: return (data.users.count, AdminTheme.muted)
            default: return nil
            }
        }()
        return Button { page = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .frame(width: 18)
                    .foregroundColor(selected ? AdminTheme.amber : .white.opacity(0.6))
                    .accessibilityHidden(true)
                Text(item.rawValue)
                    .font(.appFont(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? .white : .white.opacity(0.75))
                Spacer()
                if let badge {
                    Text("\(badge.count)")
                        .font(.appFont(size: 11, weight: .semibold))
                        .foregroundColor(badge.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Restrained selected state: a faint glass fill with a thin rim, no solid colour block.
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.07) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.white.opacity(0.12) : .clear, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.rawValue).font(.appFont(size: 20, weight: .bold)).foregroundColor(.white)
                Text(page.summary).font(.appFont(size: 12)).foregroundColor(AdminTheme.muted)
            }
            Spacer()
            if autoRefresh {
                AdminStatus(state: .good, text: "Live")
                    .help("Refreshing every second")
            } else if let generated = data.generatedAt {
                Text("Updated \(generated.formatted(date: .omitted, time: .shortened))")
                    .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
            }
            AdminSegmented(options: AdminRange.allCases, selection: Binding(get: { range }, set: { rangeValue = $0.rawValue })) { $0.label }
                .help("Time window for charts and comparisons")
            Button {
                Task { await admin.refresh() }
            } label: {
                Label(admin.isLoading ? "Loading…" : "Refresh", systemImage: "arrow.clockwise")
                    .font(.appFont(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AdminTheme.amber))
            }
            .buttonStyle(.plain)
            .disabled(admin.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            if admin.isLoading { LogoTraceLoader(size: 16, strokeWidth: 9) }
            Text(admin.isLoading ? "Loading the overview…" : "Nothing loaded yet. Press Refresh.")
                .font(.appFont(size: 12)).foregroundColor(AdminTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - Building blocks

/// A titled panel. `trailing` sits on the right of the title row (a link, a count, a picker).
struct AdminPanel<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.appFont(size: 14, weight: .bold)).foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AdminTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))
    }
}

extension AdminPanel where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
        self.content = content
    }
}

/// A change against the previous period, shown as "▲ 25%" in green or "▼ 10%" in red.
struct AdminDelta {
    let current: Double
    let previous: Double

    var text: String {
        if previous == 0 { return current == 0 ? "no change" : "new" }
        let change = (current - previous) / previous * 100
        if abs(change) < 0.5 { return "no change" }
        return "\(change > 0 ? "▲" : "▼") \(Int(abs(change).rounded()))%"
    }
    var color: Color {
        if previous == 0 && current == 0 { return AdminTheme.muted }
        if current > previous { return AdminTheme.green }
        if current < previous { return AdminTheme.red }
        return AdminTheme.muted
    }
}

/// One headline number with a label and a short note (or a change against the previous period).
struct AdminKPI: View {
    let label: String
    let value: String
    var note: String? = nil
    var delta: AdminDelta? = nil
    var tint: Color = .white
    /// A small trend line under the number (oldest first).
    var spark: [Int]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.appFont(size: 11, weight: .semibold)).foregroundColor(AdminTheme.muted)
                .lineLimit(1)
            Text(value)
                .font(.appFont(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let delta {
                Text(delta.text).font(.appFont(size: 11, weight: .semibold)).foregroundColor(delta.color)
            }
            if let note {
                Text(note).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let spark, spark.count > 1 {
                Chart(Array(spark.enumerated()), id: \.offset) { point in
                    AreaMark(x: .value("Day", point.offset), y: .value("Value", point.element))
                        .foregroundStyle(LinearGradient(colors: [AdminTheme.teal.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", point.offset), y: .value("Value", point.element))
                        .foregroundStyle(AdminTheme.teal)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 28)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AdminTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A row of KPI tiles: equal widths that fill the row, all as tall as the tallest one.
struct AdminKPIRow<Content: View>: View {
    var minimum: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 14, content: content)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row of panels side by side, all stretched to the height of the tallest, so the grid lines up.
struct AdminBentoRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 16, content: content)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A compact segmented control in the console's style.
struct AdminSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.appFont(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundColor(selected ? .white : AdminTheme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Color.white.opacity(0.1) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))
    }
}

/// Underlined tabs for a page's sub-sections.
struct AdminTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let label: (Tab) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                ForEach(tabs, id: \.self) { tab in
                    let selected = tab == selection
                    Button { selection = tab } label: {
                        VStack(spacing: 8) {
                            Text(label(tab))
                                .font(.appFont(size: 13, weight: selected ? .semibold : .medium))
                                .foregroundColor(selected ? .white : AdminTheme.muted)
                            Rectangle().fill(selected ? AdminTheme.amber : .clear).frame(height: 2)
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Rectangle().fill(AdminTheme.faint).frame(height: 1)
        }
    }
}

/// A small coloured status dot with a label.
struct AdminStatus: View {
    enum State { case good, warning, bad, neutral }
    let state: State
    let text: String

    var color: Color {
        switch state {
        case .good: return AdminTheme.green
        case .warning: return AdminTheme.amber
        case .bad: return AdminTheme.red
        case .neutral: return AdminTheme.muted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(.appFont(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85))
        }
    }
}

/// A label/value line, used in detail lists.
struct AdminRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.appFont(size: 12)).foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 12)
            Text(value).font(.appFont(size: 12, weight: .semibold)).monospacedDigit().foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
    }
}

struct AdminDivider: View {
    var body: some View { Rectangle().fill(AdminTheme.faint).frame(height: 1) }
}

struct AdminEmpty: View {
    let text: String
    var body: some View {
        Text(text).font(.appFont(size: 12)).foregroundColor(AdminTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Open Users ›" style link to another page.
struct AdminLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.appFont(size: 11, weight: .semibold))
            .foregroundColor(AdminTheme.amber)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The console's chart axes: faint grid, muted labels, dates on the x axis every `dayStride` days.
    func adminAxes(dayStride: Int) -> some View {
        chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(AdminTheme.faint)
                AxisValueLabel().foregroundStyle(AdminTheme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayStride)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(AdminTheme.muted)
            }
        }
    }

    /// Horizontal bar charts: no x axis, category labels on the left.
    func adminBarAxes() -> some View {
        chartXAxis(.hidden)
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.white.opacity(0.75)) } }
    }
}

enum AdminFormat {
    static func percent(_ part: Int, of whole: Int) -> String {
        whole == 0 ? "0%" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
    static func relative(_ date: Date?) -> String {
        date.map { $0.formatted(.relative(presentation: .named)) } ?? "never"
    }
    static func provider(_ raw: String) -> String {
        raw == "google" ? "Google" : raw == "email" ? "Email" : raw.capitalized
    }
}
