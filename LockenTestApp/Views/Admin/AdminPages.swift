import Charts
import SwiftUI

// MARK: - Overview

/// The command center: headline numbers, what needs attention, recent activity, and routes to the deeper pages.
struct AdminOverviewPage: View {
    let data: AdminData
    let range: AdminRange
    let open: (AdminPage) -> Void

    private var days: Int { range.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Row 1: health and growth.
            AdminKPIRow {
                AdminKPI(label: "Accounts", value: "\(data.users.count)", note: "\(data.google) Google · \(data.users.count - data.google) email")
                AdminKPI(label: "Active today", value: "\(data.activeToday)", note: "of \(data.users.count) accounts")
                AdminKPI(label: "Active, \(range.phrase)", value: "\(data.activePeople(days: days))",
                         note: "vs the period before",
                         delta: AdminDelta(current: Double(data.activePeople(days: days)), previous: Double(data.activePeople(days: days, offset: 1))),
                         spark: data.days(days).map(\.active))
                AdminKPI(label: "New sign-ups", value: "\(data.signups(days: days))", note: range.phrase,
                         delta: AdminDelta(current: Double(data.signups(days: days)), previous: Double(data.signups(days: days, offset: 1))),
                         spark: data.days(days).map(\.signups))
                AdminKPI(label: "Weekly / monthly active", value: "\(data.weeklyActive) / \(data.monthlyActive)",
                         note: "\(AdminFormat.percent(data.weeklyActive, of: data.monthlyActive)) come back weekly")
                AdminKPI(label: "Update server", value: data.updateServer.reachable ? "Up" : "Down",
                         note: data.updateServer.ms.map { "\($0) ms · \(data.liveVersion ?? "")" } ?? "no answer",
                         tint: data.updateServer.reachable ? AdminTheme.green : AdminTheme.red)
            }

            // Row 2: product activity and integration health.
            AdminBentoRow {
                AdminPanel(title: "Daily active people", subtitle: "\(range.phrase.capitalized), with \(range.previousPhrase) dashed for comparison",
                           trailing: { AdminLink(title: "Analytics") { open(.analytics) } }) {
                    activityChart
                }
                AdminPanel(title: "Integration health", subtitle: "Checked on this refresh",
                           trailing: { AdminLink(title: "Details") { open(.integrations) } }) {
                    VStack(alignment: .leading, spacing: 0) {
                        healthLine("Google sign-in", method("google"))
                        AdminDivider()
                        healthLine("Email sign-in & codes", method("email"))
                        AdminDivider()
                        HStack {
                            AdminStatus(state: data.updateServer.reachable ? .good : .bad, text: "Update server")
                            Spacer()
                            Text(data.updateServer.ms.map { "\($0) ms" } ?? "down").font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                        }
                        .padding(.vertical, 9)
                        AdminDivider()
                        HStack {
                            AdminStatus(state: data.databaseOK ? .good : .bad, text: "Database")
                            Spacer()
                            Text(data.databaseMs.map { "\($0) ms · \(String(format: "%.1f", data.database.sizeMB)) MB" } ?? "–")
                                .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                        }
                        .padding(.vertical, 9)
                    }
                }
                .frame(width: 330)
            }

            // Row 3: alerts, recent activity, recent sign-ups.
            AdminBentoRow {
                AdminPanel(title: "Needs attention", subtitle: data.alerts.isEmpty ? "Nothing right now" : "\(data.alerts.count) item(s), most serious first") {
                    if data.alerts.isEmpty {
                        AdminStatus(state: .good, text: "All clear")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(data.alerts.prefix(6).enumerated()), id: \.element.id) { index, alert in
                            if index > 0 { AdminDivider() }
                            AdminAlertRow(alert: alert) { open(alert.page) }
                        }
                    }
                }
                VStack(spacing: 16) {
                    AdminPanel(title: "Recent activity", trailing: { AdminLink(title: "Events & Logs") { open(.events) } }) {
                        VStack(alignment: .leading, spacing: 0) {
                            if data.events.isEmpty { AdminEmpty(text: "Nothing recorded yet.") }
                            ForEach(Array(data.events.prefix(6).enumerated()), id: \.element.id) { index, event in
                                if index > 0 { AdminDivider() }
                                AdminEventRow(event: event, compact: true)
                            }
                        }
                    }
                    AdminPanel(title: "Recent sign-ups", trailing: { AdminLink(title: "Users") { open(.users) } }) {
                        let recent = Array(data.users.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }.prefix(4))
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, user in
                                if index > 0 { AdminDivider() }
                                HStack {
                                    Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(user.created.map { $0.formatted(.relative(presentation: .named)) } ?? "")
                                        .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
                }
                .frame(width: 400)
            }

            // Bottom: routes into the deeper pages.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                route(.analytics, "\(AdminFormat.percent(data.returningUsers, of: data.users.count)) of accounts came back on a second day")
                route(.users, "\(data.users.count) accounts · \(data.neverSignedIn) never signed in")
                route(.health, "\(data.usersOnLiveBuild) of \(data.usersWithBuild) people on the live build")
                route(.security, "\(data.twoFactorUsers) with two-factor · \(data.security.tables.filter(\.rls).count)/\(data.security.tables.count) tables protected")
            }
        }
    }

    private var activityChart: some View {
        let current = data.days(days)
        let previous = data.days(days, offset: 1)
        // The previous period is drawn on the current period's dates so the two lines overlap.
        let shifted: [(day: Date, active: Int)] = zip(current, previous).map { ($0.day, $1.active) }
        return Chart {
            ForEach(current, id: \.day) { point in
                AreaMark(x: .value("Day", point.day, unit: .day), y: .value("People", point.active))
                    .foregroundStyle(LinearGradient(colors: [AdminTheme.teal.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("People", point.active), series: .value("Period", "Now"))
                    .foregroundStyle(AdminTheme.teal)
                    .interpolationMethod(.monotone)
            }
            ForEach(shifted, id: \.day) { point in
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("People", point.active), series: .value("Period", "Before"))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
        }
        .adminAxes(dayStride: range.axisStride)
        .frame(height: 200)
    }

    private func method(_ provider: String) -> AdminData.Method? { data.methods.first { $0.provider == provider } }

    private func healthLine(_ title: String, _ method: AdminData.Method?) -> some View {
        HStack {
            AdminStatus(state: method == nil ? .neutral : .good, text: title)
            Spacer()
            Text(method.map { "\($0.accounts) · used \(AdminFormat.relative($0.lastUsed))" } ?? "not used yet")
                .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted).lineLimit(1)
        }
        .padding(.vertical, 9)
    }

    private func route(_ page: AdminPage, _ line: String) -> some View {
        Button { open(page) } label: {
            HStack(spacing: 12) {
                Image(systemName: page.icon).font(.system(size: 15)).foregroundColor(AdminTheme.amber).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.rawValue).font(.appFont(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text(line).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(AdminTheme.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AdminTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One attention item: severity dot, what's wrong, what to do, and a jump to the page that has the detail.
struct AdminAlertRow: View {
    let alert: AdminData.Alert
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(AdminTheme.color(for: alert.level)).frame(width: 8, height: 8).padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.appFont(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text(alert.detail).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(alert.page.rawValue).font(.appFont(size: 11, weight: .semibold)).foregroundColor(AdminTheme.amber)
                    .padding(.top, 2)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(alert.title). \(alert.detail)")
    }
}

/// One event line: what happened, to whom, when.
struct AdminEventRow: View {
    let event: AdminData.Event
    var compact = false

    private var color: Color {
        switch event.kind {
        case .signup: return AdminTheme.teal
        case .confirmed: return AdminTheme.green
        case .signin: return Color.white.opacity(0.55)
        case .mfa: return AdminTheme.green
        case .feedback: return AdminTheme.amber
        case .change: return AdminTheme.amber.opacity(0.7)
        }
    }

    private var detailText: String? {
        guard let detail = event.detail, !detail.isEmpty else { return nil }
        switch event.kind {
        case .signin: return "build \(detail)"
        case .feedback: return "\(detail) ★"
        case .mfa: return detail
        default: return detail
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(event.kind.label)
                .font(.appFont(size: 10, weight: .bold))
                .foregroundColor(color)
                .frame(width: compact ? 92 : 110, alignment: .leading)
            Text(event.email ?? "deleted account")
                .font(.appFont(size: 12))
                .foregroundColor(AdminTheme.text)
                .lineLimit(1).truncationMode(.middle)
            if !compact, let detailText {
                Text(detailText).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
            }
            Spacer(minLength: 8)
            Text(compact ? event.date.formatted(.relative(presentation: .named)) : event.date.formatted(date: .abbreviated, time: .shortened))
                .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Analytics

struct AdminAnalyticsPage: View {
    let data: AdminData
    let range: AdminRange

    enum Tab: String, CaseIterable { case overview = "Overview", engagement = "Engagement", retention = "Retention", feedback = "Feedback" }
    @State private var tab: Tab = .overview

    private var days: Int { range.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AdminTabs(tabs: Tab.allCases, selection: $tab) { $0.rawValue }
            switch tab {
            case .overview: overview
            case .engagement: engagement
            case .retention: retention
            case .feedback: feedback
            }
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                comparison("Active people", data.activePeople(days: days), data.activePeople(days: days, offset: 1), data.days(days).map(\.active))
                comparison("New sign-ups", data.signups(days: days), data.signups(days: days, offset: 1), data.days(days).map(\.signups))
                comparison("Sign-ins", data.signIns(days: days), data.signIns(days: days, offset: 1), data.days(days).map(\.signIns))
                comparison("App activity", data.refreshes(days: days), data.refreshes(days: days, offset: 1), data.days(days).map(\.refreshes))
            }
            AdminBentoRow {
                AdminPanel(title: "Active people per day", subtitle: range.phrase.capitalized) {
                    Chart(data.days(days), id: \.day) { point in
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("People", point.active))
                            .foregroundStyle(AdminTheme.teal).interpolationMethod(.monotone)
                        AreaMark(x: .value("Day", point.day, unit: .day), y: .value("People", point.active))
                            .foregroundStyle(LinearGradient(colors: [AdminTheme.teal.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    .adminAxes(dayStride: range.axisStride)
                    .frame(height: 190)
                }
                AdminPanel(title: "Sign-ups per day", subtitle: range.phrase.capitalized) {
                    Chart(data.days(days), id: \.day) { point in
                        BarMark(x: .value("Day", point.day, unit: .day), y: .value("Sign-ups", point.signups))
                            .foregroundStyle(AdminTheme.amber).cornerRadius(2)
                    }
                    .adminAxes(dayStride: range.axisStride)
                    .frame(height: 190)
                }
            }
            AdminBentoRow {
                AdminPanel(title: "Total accounts", subtitle: "At the end of each day") {
                    Chart(data.cumulativeAccounts(days: days), id: \.day) { point in
                        AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Accounts", point.count))
                            .foregroundStyle(LinearGradient(colors: [AdminTheme.amber.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.stepEnd)
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("Accounts", point.count))
                            .foregroundStyle(AdminTheme.amber).interpolationMethod(.stepEnd)
                    }
                    .adminAxes(dayStride: range.axisStride)
                    .frame(height: 170)
                }
                AdminPanel(title: "Sign-ins per day", subtitle: "New sessions started on a Mac") {
                    Chart(data.days(days), id: \.day) { point in
                        BarMark(x: .value("Day", point.day, unit: .day), y: .value("Sign-ins", point.signIns))
                            .foregroundStyle(AdminTheme.teal.opacity(0.8)).cornerRadius(2)
                    }
                    .adminAxes(dayStride: range.axisStride)
                    .frame(height: 170)
                }
            }
        }
    }

    private func comparison(_ label: String, _ current: Int, _ previous: Int, _ spark: [Int]) -> AdminKPI {
        AdminKPI(label: label, value: "\(current)", note: "vs \(previous) the period before",
                 delta: AdminDelta(current: Double(current), previous: Double(previous)), spark: spark)
    }

    // MARK: Engagement

    private var engagement: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Average active per day", value: String(format: "%.1f", data.averageDailyActive(days: days)), note: range.phrase)
                AdminKPI(label: "Weekly ÷ monthly", value: AdminFormat.percent(data.weeklyActive, of: data.monthlyActive),
                         note: "of this month's people used it this week")
                AdminKPI(label: "Came back", value: "\(data.returningUsers)", note: "used it on 2 or more days")
                AdminKPI(label: "One day only", value: "\(data.oneDayUsers)", note: "tried it once")
            }
            AdminPanel(title: "App activity", subtitle: "Session refreshes per day; more means the app stayed open longer") {
                Chart(data.days(days), id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("Refreshes", point.refreshes))
                        .foregroundStyle(AdminTheme.teal.opacity(0.85)).cornerRadius(2)
                }
                .adminAxes(dayStride: range.axisStride)
                .frame(height: 180)
            }
            AdminBentoRow {
                AdminPanel(title: "Days used", subtitle: "How many days each account has opened Locken") {
                    Chart(data.activeDayGroups(), id: \.label) { bucket in
                        BarMark(x: .value("Accounts", bucket.count), y: .value("Days", bucket.label))
                            .foregroundStyle(bucket.label == "Never used" ? Color.white.opacity(0.25) : AdminTheme.teal)
                            .cornerRadius(3)
                            .annotation(position: .trailing) {
                                Text("\(bucket.count)").font(.appFont(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            }
                    }
                    .adminBarAxes()
                    .frame(height: 170)
                }
                AdminPanel(title: "Last seen", subtitle: "When each account last signed in") {
                    Chart(data.recency(), id: \.label) { bucket in
                        BarMark(x: .value("Accounts", bucket.count), y: .value("When", bucket.label))
                            .foregroundStyle(bucket.label == "Never" ? Color.white.opacity(0.25) : AdminTheme.amber)
                            .cornerRadius(3)
                            .annotation(position: .trailing) {
                                Text("\(bucket.count)").font(.appFont(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            }
                    }
                    .adminBarAxes()
                    .frame(height: 170)
                }
            }
            AdminPanel(title: "Most active people", subtitle: "Ranked by days they used Locken") {
                let top = data.mostActive(limit: 8)
                if top.isEmpty { AdminEmpty(text: "No activity recorded yet.") }
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { AdminDivider() }
                        HStack(spacing: 12) {
                            Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text)
                                .frame(width: 260, alignment: .leading).lineLimit(1).truncationMode(.middle)
                            GeometryReader { geo in
                                let best = Double(max(top.first?.usage?.activeDays ?? 1, 1))
                                Capsule().fill(AdminTheme.teal.opacity(0.8))
                                    .frame(width: max(4, geo.size.width * Double(user.usage?.activeDays ?? 0) / best), height: 6)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: 14)
                            Text("\(user.usage?.activeDays ?? 0) days").font(.appFont(size: 12, weight: .semibold))
                                .foregroundColor(.white).frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    // MARK: Retention

    private var retention: some View {
        let cohorts = data.cohorts()
        return VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Came back on a second day", value: AdminFormat.percent(data.returningUsers, of: data.users.count),
                         note: "\(data.returningUsers) of \(data.users.count) accounts")
                AdminKPI(label: "Tried it once", value: AdminFormat.percent(data.oneDayUsers, of: data.users.count),
                         note: "\(data.oneDayUsers) accounts")
                AdminKPI(label: "Never used it", value: "\(max(0, data.users.count - data.returningUsers - data.oneDayUsers))",
                         note: "made an account only")
            }
            AdminPanel(title: "Weekly cohorts", subtitle: "People grouped by the week they signed up, and the share active in each week after") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Signed up").frame(width: 120, alignment: .leading)
                        Text("People").frame(width: 56, alignment: .trailing)
                        ForEach(0..<5, id: \.self) { week in
                            Text(week == 0 ? "Week 0" : "Week \(week)").frame(maxWidth: .infinity)
                        }
                    }
                    .font(.appFont(size: 11, weight: .semibold))
                    .foregroundColor(AdminTheme.muted)
                    ForEach(cohorts) { cohort in
                        HStack(spacing: 6) {
                            Text(cohort.id.formatted(.dateTime.month(.abbreviated).day())).frame(width: 120, alignment: .leading)
                                .foregroundColor(AdminTheme.text)
                            Text("\(cohort.size)").frame(width: 56, alignment: .trailing).foregroundColor(AdminTheme.text)
                            ForEach(Array(cohort.weeks.enumerated()), id: \.offset) { _, share in
                                cohortCell(share, empty: cohort.size == 0)
                            }
                        }
                        .font(.appFont(size: 12))
                        .monospacedDigit()
                    }
                }
            }
            AdminEmpty(text: "Week 0 is the week they signed up. Active means the app refreshed their sign-in that week.")
        }
    }

    private func cohortCell(_ share: Double?, empty: Bool) -> some View {
        let text = empty ? "" : share.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return Text(text)
            .font(.appFont(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(AdminTheme.teal.opacity(empty ? 0 : 0.08 + 0.6 * (share ?? 0))))
    }

    // MARK: Feedback

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Messages", value: "\(data.feedback.count)", note: "from \(Set(data.feedback.map(\.email)).count) people")
                AdminKPI(label: "Average rating", value: data.averageRating.map { String(format: "%.1f ★", $0) } ?? "–", note: "\(data.ratings.count) ratings")
                AdminKPI(label: "Low ratings", value: "\(data.ratings.filter { $0 <= 2 }.count)", note: "1 or 2 stars")
            }
            AdminPanel(title: "Ratings", subtitle: "How many people gave each score") {
                Chart(data.ratingCounts(), id: \.stars) { item in
                    BarMark(x: .value("Stars", "\(item.stars) ★"), y: .value("Count", item.count))
                        .foregroundStyle(AdminTheme.amber).cornerRadius(3)
                }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(AdminTheme.faint); AxisValueLabel().foregroundStyle(AdminTheme.muted) } }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.white.opacity(0.7)) } }
                .frame(height: 150)
            }
            AdminPanel(title: "Messages", subtitle: "Newest first") {
                if data.feedback.isEmpty {
                    AdminEmpty(text: "No feedback yet. People are asked after a week, or can send it from Settings.")
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.feedback.enumerated()), id: \.offset) { index, item in
                        if index > 0 { AdminDivider() }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.email).font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white)
                                if let rating = item.rating {
                                    Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                                        .font(.system(size: 11)).foregroundColor(AdminTheme.amber)
                                        .accessibilityLabel("\(rating) out of 5 stars")
                                }
                                Spacer()
                                Text([item.date.map { $0.formatted(date: .abbreviated, time: .shortened) }, item.version].compactMap { $0 }.joined(separator: " · "))
                                    .font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                            }
                            if !item.message.isEmpty {
                                Text(item.message).font(.appFont(size: 13)).foregroundColor(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

// MARK: - Users

struct AdminUsersPage: View {
    let data: AdminData

    enum Filter: String, CaseIterable {
        case all = "All", active = "Active this week", never = "Never signed in", unconfirmed = "Unconfirmed"
        case outdated = "Not updated", google = "Google", email = "Email"
    }
    enum Sort: String, CaseIterable { case lastSeen = "Last seen", joined = "Joined", activeDays = "Days used", email = "Email" }

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .lastSeen
    @State private var selectedID: String?

    private var rows: [AdminData.User] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let outdated = Set(data.usersOnOldBuilds.map(\.id))
        return data.users
            .filter { query.isEmpty || $0.email.lowercased().contains(query) }
            .filter { user in
                switch filter {
                case .all: return true
                case .active: return (user.lastSeen ?? .distantPast) > weekAgo
                case .never: return user.lastSeen == nil
                case .unconfirmed: return !user.confirmed
                case .outdated: return outdated.contains(user.id)
                case .google: return user.provider == "google"
                case .email: return user.provider != "google"
                }
            }
            .sorted { a, b in
                switch sort {
                case .lastSeen: return (a.lastSeen ?? .distantPast) > (b.lastSeen ?? .distantPast)
                case .joined: return (a.created ?? .distantPast) > (b.created ?? .distantPast)
                case .activeDays: return (a.usage?.activeDays ?? 0) > (b.usage?.activeDays ?? 0)
                case .email: return a.email < b.email
                }
            }
    }

    private var selected: AdminData.User? { data.users.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Accounts", value: "\(data.users.count)", note: "\(data.newUsers(days: 7).count) new this week")
                AdminKPI(label: "Never signed in", value: "\(data.neverSignedIn)", note: "made an account only")
                AdminKPI(label: "Email not confirmed", value: "\(data.unconfirmed)", note: "code never entered")
                AdminKPI(label: "Not updated", value: "\(data.usersOnOldBuilds.count)", note: "on an older build")
            }

            toolbar

            AdminBentoRow {
                table
                if let selected {
                    AdminUserDetail(user: selected, liveBuild: data.liveBuild) { selectedID = nil }
                        .frame(width: 320)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: selectedID)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(AdminTheme.muted)
                TextField("Search email", text: $search)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 12))
                    .foregroundColor(.white)
                    .accessibilityLabel("Search accounts by email")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))

            Menu {
                ForEach(Filter.allCases, id: \.self) { option in
                    Button(option.rawValue) { filter = option }
                }
            } label: {
                Label(filter.rawValue, systemImage: "line.3.horizontal.decrease")
                    .font(.appFont(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filter accounts")

            Menu {
                ForEach(Sort.allCases, id: \.self) { option in
                    Button(option.rawValue) { sort = option }
                }
            } label: {
                Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
                    .font(.appFont(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort accounts")

            Spacer()
            Text("\(rows.count) shown").font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
        }
    }

    private var table: some View {
        AdminPanel(title: "Accounts", subtitle: "Click a row for details") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Email").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Sign-in").frame(width: 58, alignment: .leading)
                    Text("Build").frame(width: 44, alignment: .leading)
                    Text("Days").frame(width: 40, alignment: .trailing)
                    Text("Joined").frame(width: 90, alignment: .leading)
                    Text("Last seen").frame(width: 100, alignment: .leading)
                }
                .font(.appFont(size: 11, weight: .semibold))
                .foregroundColor(AdminTheme.muted)
                .padding(.vertical, 8)
                if rows.isEmpty {
                    AdminDivider()
                    AdminEmpty(text: "No accounts match.").padding(.vertical, 12)
                }
                ForEach(rows) { user in
                    AdminDivider()
                    row(user)
                }
            }
        }
    }

    private func row(_ user: AdminData.User) -> some View {
        let isSelected = user.id == selectedID
        return Button { selectedID = isSelected ? nil : user.id } label: {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(user.email).lineLimit(1).truncationMode(.middle)
                    if user.isAdmin {
                        Text("admin").font(.appFont(size: 9, weight: .bold)).foregroundColor(AdminTheme.amber)
                    }
                    if !user.confirmed {
                        Text("unconfirmed").font(.appFont(size: 9, weight: .bold)).foregroundColor(AdminTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(AdminFormat.provider(user.provider)).frame(width: 58, alignment: .leading)
                    .foregroundColor(user.provider == "google" ? AdminTheme.teal : AdminTheme.amber)
                Text(user.usage?.build ?? "–").frame(width: 44, alignment: .leading)
                    .foregroundColor(buildColor(user.usage?.build))
                Text("\(user.usage?.activeDays ?? 0)").frame(width: 40, alignment: .trailing)
                Text(user.created.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "").frame(width: 90, alignment: .leading)
                Text(AdminFormat.relative(user.lastSeen)).frame(width: 100, alignment: .leading)
                    .foregroundColor(user.lastSeen == nil ? AdminTheme.muted : .white.opacity(0.85))
            }
            .font(.appFont(size: 12))
            .monospacedDigit()
            .foregroundColor(AdminTheme.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func buildColor(_ build: String?) -> Color {
        guard let build, let live = data.liveBuild else { return AdminTheme.muted }
        return build == "\(live)" ? AdminTheme.teal : AdminTheme.amber
    }
}

/// The selected account: identity, activity over the last 30 days, sessions and security.
struct AdminUserDetail: View {
    let user: AdminData.User
    let liveBuild: Int?
    let close: () -> Void

    var body: some View {
        AdminPanel(title: user.email, subtitle: user.isAdmin ? "Admin account" : AdminFormat.provider(user.provider) + " account",
                   trailing: {
                       Button(action: close) {
                           Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(AdminTheme.muted)
                       }
                       .buttonStyle(.plain)
                       .accessibilityLabel("Close details")
                   }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Last 30 days").font(.appFont(size: 11, weight: .semibold)).foregroundColor(AdminTheme.muted)
                    .padding(.bottom, 6)
                activityStrip
                    .padding(.bottom, 10)
                AdminRow(label: "Joined", value: user.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "–")
                AdminDivider()
                AdminRow(label: "Last signed in", value: AdminFormat.relative(user.lastSeen))
                AdminDivider()
                AdminRow(label: "Days used", value: "\(user.usage?.activeDays ?? 0)")
                AdminDivider()
                AdminRow(label: "Build", value: buildText, valueColor: buildIsLive ? AdminTheme.teal : .white)
                AdminDivider()
                AdminRow(label: "Signed-in Macs", value: "\(user.usage?.liveSessions ?? 0) now · \(user.usage?.sessions ?? 0) total")
                AdminDivider()
                AdminRow(label: "Email confirmed", value: user.confirmed ? "Yes" : "No", valueColor: user.confirmed ? .white : AdminTheme.amber)
                AdminDivider()
                AdminRow(label: "Two-factor", value: (user.usage?.mfa ?? false) ? "On" : "Off",
                         valueColor: (user.usage?.mfa ?? false) ? AdminTheme.green : .white)
                AdminDivider()
                AdminRow(label: "Account ID", value: String(user.id.prefix(8)) + "…")
            }
        }
    }

    private var buildIsLive: Bool { user.usage?.build != nil && user.usage?.build == liveBuild.map { "\($0)" } }
    private var buildText: String {
        guard let build = user.usage?.build else { return "–" }
        return buildIsLive ? "\(build) (live)" : build
    }

    /// One square per day for the last 30 days; filled when they used Locken that day.
    private var activityStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let active = Set(user.usage?.activeDates ?? [])
        let days: [Date] = (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(active.contains(day) ? AdminTheme.teal : Color.white.opacity(0.07))
                    .frame(height: 14)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Used Locken on \(days.filter { active.contains($0) }.count) of the last 30 days")
    }
}
