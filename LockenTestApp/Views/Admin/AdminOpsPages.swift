import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Integrations

/// Each outside service Locken depends on, with its status and the numbers behind it.
struct AdminIntegrationsPage: View {
    let data: AdminData

    private func method(_ provider: String) -> AdminData.Method? { data.methods.first { $0.provider == provider } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                signInCard(title: "Google sign-in", provider: "google",
                           note: "OAuth through Supabase with PKCE. New Google accounts go through the consent screen first.")
                signInCard(title: "Email sign-in & codes", provider: "email",
                           note: "Password plus a 6-digit email code. Unconfirmed accounts started sign-up but never entered the code.") {
                    AdminDivider()
                    AdminRow(label: "Unconfirmed accounts", value: "\(data.unconfirmed)", valueColor: data.unconfirmed > 0 ? AdminTheme.amber : .white)
                }
                AdminPanel(title: "Update server", subtitle: "locken-app.vercel.app · signed version.json and DMG",
                           trailing: { AdminStatus(state: data.updateServer.reachable ? .good : .bad, text: data.updateServer.reachable ? "Up" : "Down") }) {
                    VStack(spacing: 0) {
                        AdminRow(label: "Response", value: data.updateServer.ms.map { "\($0) ms" } ?? "no answer")
                        AdminDivider()
                        AdminRow(label: "HTTP status", value: data.updateServer.status.map(String.init) ?? "–")
                        AdminDivider()
                        AdminRow(label: "Live version", value: [data.liveVersion, data.liveBuild.map { "build \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        AdminDivider()
                        AdminRow(label: "Maintenance mode", value: data.maintenanceMode ? "On" : "Off",
                                 valueColor: data.maintenanceMode ? AdminTheme.amber : .white)
                    }
                }
                AdminPanel(title: "Supabase", subtitle: "Accounts, database and the admin function",
                           trailing: { AdminStatus(state: data.databaseOK ? .good : .bad, text: data.databaseOK ? "Up" : "Error") }) {
                    VStack(spacing: 0) {
                        AdminRow(label: "Analytics query", value: data.databaseMs.map { "\($0) ms" } ?? "–")
                        AdminDivider()
                        AdminRow(label: "Database size", value: String(format: "%.1f MB of 500 MB", data.database.sizeMB))
                        AdminDivider()
                        AdminRow(label: "Signed-in sessions", value: "\(data.liveSessions)")
                        AdminDivider()
                        AdminRow(label: "Tables with Row Level Security", value: "\(data.security.tables.filter(\.rls).count) of \(data.security.tables.count)")
                    }
                }
            }
            AdminPanel(title: "On students' Macs only", subtitle: "These connect from each Mac with the student's own access; the server never sees them") {
                VStack(spacing: 0) {
                    localRow("Canvas", "Student's own Canvas link or token, in their Keychain")
                    AdminDivider()
                    localRow("Claude / Gemini (AI)", "Student's own API key, 18+ only")
                    AdminDivider()
                    localRow("Apple Notes, Reminders, Calendar", "macOS permissions on that Mac")
                    AdminDivider()
                    localRow("YouTube video checks", "Public oEmbed lookups of title and channel")
                }
            }
        }
    }

    private func signInCard(title: String, provider: String, note: String) -> some View {
        signInCard(title: title, provider: provider, note: note) { EmptyView() }
    }

    private func signInCard<Extra: View>(title: String, provider: String, note: String, @ViewBuilder extra: () -> Extra) -> some View {
        let method = method(provider)
        let extraView = extra()
        return AdminPanel(title: title, subtitle: note,
                          trailing: { AdminStatus(state: method == nil ? .neutral : .good, text: method == nil ? "Unused" : "Working") }) {
            VStack(spacing: 0) {
                AdminRow(label: "Accounts", value: "\(method?.accounts ?? 0)")
                AdminDivider()
                AdminRow(label: "New in the last 30 days", value: "\(method?.newLast30 ?? 0)")
                AdminDivider()
                AdminRow(label: "Last used", value: AdminFormat.relative(method?.lastUsed))
                extraView
            }
        }
    }

    private func localRow(_ name: String, _ how: String) -> some View {
        HStack {
            Text(name).font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text(how).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - AI & Usage

/// What Locken uses of its free plans, and why AI cost isn't on the server.
struct AdminUsagePage: View {
    let data: AdminData
    let range: AdminRange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Database", value: String(format: "%.1f MB", data.database.sizeMB), note: "of 500 MB free")
                AdminKPI(label: "Monthly active", value: "\(data.monthlyActive)", note: "of 50,000 free sign-ins")
                AdminKPI(label: "Sign-ins", value: "\(data.signIns(days: range.rawValue))", note: range.phrase)
                AdminKPI(label: "App activity", value: "\(data.refreshes(days: range.rawValue))", note: "session refreshes, \(range.phrase)")
            }
            AdminBentoRow {
                AdminPanel(title: "Free plan limits", subtitle: "Supabase free tier") {
                    VStack(alignment: .leading, spacing: 14) {
                        meter("Database", used: data.database.sizeMB, limit: 500, unit: "MB")
                        meter("Monthly active people", used: Double(data.monthlyActive), limit: 50_000, unit: "")
                    }
                }
                AdminPanel(title: "Rows stored", subtitle: "What the database holds") {
                    VStack(spacing: 0) {
                        AdminRow(label: "Profiles", value: "\(data.database.profiles)")
                        AdminDivider()
                        AdminRow(label: "Focus sessions synced", value: "\(data.database.focusSessions)")
                        AdminDivider()
                        AdminRow(label: "Feedback", value: "\(data.database.feedback)")
                        AdminDivider()
                        AdminRow(label: "Audit log entries", value: "\(data.database.auditEntries)")
                        AdminDivider()
                        AdminRow(label: "Waitlist emails", value: "\(data.database.waitlist)")
                    }
                }
                .frame(width: 340)
            }
            AdminPanel(title: "AI requests and cost", subtitle: "Not tracked, by design") {
                AdminEmpty(text: "Intelligent Rephrase, milestones and digests run on each student's own Claude or Gemini key, straight from their Mac (18+ only). Locken pays nothing for AI and never sees the requests, so there's no count or cost to show here.")
            }
        }
    }

    private func meter(_ label: String, used: Double, limit: Double, unit: String) -> some View {
        let share = min(used / limit, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text(unit.isEmpty ? "\(Int(used)) of \(Int(limit).formatted())" : String(format: "%.1f of %.0f \(unit)", used, limit))
                    .font(.appFont(size: 11)).monospacedDigit().foregroundColor(AdminTheme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(share > 0.8 ? AdminTheme.amber : AdminTheme.teal).frame(width: max(6, geo.size.width * share))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - System Health

struct AdminHealthPage: View {
    let data: AdminData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Update server", value: data.updateServer.reachable ? "Up" : "Down",
                         note: data.updateServer.ms.map { "\($0) ms" } ?? "no answer",
                         tint: data.updateServer.reachable ? AdminTheme.green : AdminTheme.red)
                AdminKPI(label: "Database", value: data.databaseOK ? "Up" : "Error",
                         note: data.databaseMs.map { "query took \($0) ms" } ?? "",
                         tint: data.databaseOK ? AdminTheme.green : AdminTheme.red)
                AdminKPI(label: "Live version", value: data.liveVersion ?? "–", note: data.liveBuild.map { "build \($0)" } ?? "")
                AdminKPI(label: "On the live build", value: "\(data.usersOnLiveBuild) of \(data.usersWithBuild)",
                         note: "\(data.usersOnOldBuilds.count) not updated")
            }
            AdminBentoRow {
                AdminPanel(title: "Builds in use", subtitle: "The build each person last signed in with") {
                    if data.builds.isEmpty {
                        AdminEmpty(text: "No builds reported yet.")
                    } else {
                        Chart(data.builds, id: \.build) { item in
                            BarMark(x: .value("People", item.users), y: .value("Build", "Build \(item.build)"))
                                .foregroundStyle(item.build == data.liveBuild.map { "\($0)" } ? AdminTheme.teal : AdminTheme.amber)
                                .cornerRadius(3)
                                .annotation(position: .trailing) {
                                    Text("\(item.users)").font(.appFont(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                                }
                        }
                        .adminBarAxes()
                        .frame(height: max(120, CGFloat(data.builds.count) * 34))
                    }
                }
                AdminPanel(title: "Not updated yet", subtitle: "Still on an older build") {
                    if data.usersOnOldBuilds.isEmpty { AdminStatus(state: .good, text: "Everyone is up to date") }
                    VStack(spacing: 0) {
                        ForEach(Array(data.usersOnOldBuilds.enumerated()), id: \.element.id) { index, user in
                            if index > 0 { AdminDivider() }
                            HStack {
                                Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("build \(user.usage?.build ?? "?")").font(.appFont(size: 11)).foregroundColor(AdminTheme.amber)
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
                .frame(width: 340)
            }
            AdminPanel(title: "What's live", subtitle: "From version.json on the update server") {
                VStack(spacing: 0) {
                    AdminRow(label: "Version", value: data.liveVersion ?? "–")
                    AdminDivider()
                    AdminRow(label: "Build", value: data.liveBuild.map(String.init) ?? "–")
                    AdminDivider()
                    AdminRow(label: "What's new note", value: data.liveNotes ?? "–")
                    AdminDivider()
                    AdminRow(label: "Maintenance mode", value: data.maintenanceMode ? "On" : "Off")
                }
            }
        }
    }
}

// MARK: - Events & Logs

struct AdminEventsPage: View {
    let data: AdminData
    let range: AdminRange

    @State private var kind: AdminData.Event.Kind?
    @State private var search = ""

    private var rows: [AdminData.Event] {
        let cutoff = Date().addingTimeInterval(-Double(range.rawValue) * 86400)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return data.events.filter { event in
            event.date > cutoff
                && (kind == nil || event.kind == kind)
                && (query.isEmpty || (event.email ?? "").lowercased().contains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow(minimum: 140) {
                ForEach(AdminData.Event.Kind.allCases, id: \.self) { kind in
                    AdminKPI(label: kind.label, value: "\(count(kind))", note: range.phrase)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(AdminTheme.muted)
                    TextField("Search email", text: $search)
                        .textFieldStyle(.plain)
                        .font(.appFont(size: 12))
                        .foregroundColor(.white)
                        .accessibilityLabel("Search events by email")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 240)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminTheme.faint, lineWidth: 1))
                Menu {
                    Button("All events") { kind = nil }
                    Divider()
                    ForEach(AdminData.Event.Kind.allCases, id: \.self) { option in
                        Button(option.label) { kind = option }
                    }
                } label: {
                    Label(kind?.label ?? "All events", systemImage: "line.3.horizontal.decrease").font(.appFont(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Text("\(rows.count) in the \(range.phrase)").font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
            }
            AdminPanel(title: "Event log", subtitle: "Up to the latest 200 events. Values that changed are never shown, only what changed.") {
                if rows.isEmpty { AdminEmpty(text: "No events match.") }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { AdminDivider() }
                        AdminEventRow(event: event)
                    }
                }
            }
        }
    }

    private func count(_ kind: AdminData.Event.Kind) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(range.rawValue) * 86400)
        return data.events.filter { $0.kind == kind && $0.date > cutoff }.count
    }
}

// MARK: - Security

struct AdminSecurityPage: View {
    let data: AdminData

    private var checks: [(title: String, detail: String, ok: Bool)] {
        let unprotected = data.security.tables.filter { !$0.rls }.map(\.name)
        return [
            ("Row Level Security on every table",
             unprotected.isEmpty ? "\(data.security.tables.count) tables, all protected" : "Off for \(unprotected.joined(separator: ", "))",
             unprotected.isEmpty),
            ("No server functions open to app users",
             data.security.exposedFunctions.isEmpty ? "Privileged functions run for the server only" : data.security.exposedFunctions.joined(separator: ", "),
             data.security.exposedFunctions.isEmpty),
            ("Admin data checked on the server",
             "This console's data comes from admin-overview, which refuses anyone not in public.admins",
             true),
            ("No account signed in on more than 5 Macs",
             data.manySessionUsers.isEmpty ? "Largest is \(data.users.map { $0.usage?.liveSessions ?? 0 }.max() ?? 0)" : "\(data.manySessionUsers.count) account(s) over 5",
             data.manySessionUsers.isEmpty),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminKPIRow {
                AdminKPI(label: "Checks passing", value: "\(checks.filter(\.ok).count) of \(checks.count)",
                         tint: checks.allSatisfy(\.ok) ? AdminTheme.green : AdminTheme.amber)
                AdminKPI(label: "Two-factor on", value: "\(data.twoFactorUsers)", note: "\(AdminFormat.percent(data.twoFactorUsers, of: data.users.count)) of accounts")
                AdminKPI(label: "Signed-in sessions", value: "\(data.liveSessions)", note: "across all Macs")
                AdminKPI(label: "Admins", value: "\(data.security.adminIDs.count)", note: "listed in public.admins")
            }
            AdminPanel(title: "Checks", subtitle: "Run against the live database on this refresh") {
                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                        if index > 0 { AdminDivider() }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(check.ok ? AdminTheme.green : AdminTheme.red)
                                .accessibilityLabel(check.ok ? "Passing" : "Failing")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title).font(.appFont(size: 13, weight: .semibold)).foregroundColor(.white)
                                Text(check.detail).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
            AdminBentoRow {
                AdminPanel(title: "Most signed-in Macs", subtitle: "Accounts by sessions that are still valid") {
                    let ranked = Array(data.users.filter { ($0.usage?.liveSessions ?? 0) > 0 }
                        .sorted { ($0.usage?.liveSessions ?? 0) > ($1.usage?.liveSessions ?? 0) }.prefix(8))
                    if ranked.isEmpty { AdminEmpty(text: "No one is signed in.") }
                    VStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, user in
                            if index > 0 { AdminDivider() }
                            HStack {
                                Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(user.usage?.liveSessions ?? 0)").font(.appFont(size: 12, weight: .semibold)).monospacedDigit()
                                    .foregroundColor((user.usage?.liveSessions ?? 0) > 5 ? AdminTheme.red : .white)
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
                AdminPanel(title: "Table protection", subtitle: "Row Level Security per table") {
                    VStack(spacing: 0) {
                        ForEach(Array(data.security.tables.enumerated()), id: \.offset) { index, table in
                            if index > 0 { AdminDivider() }
                            HStack {
                                Text(table.name).font(.system(size: 12, design: .monospaced)).foregroundColor(AdminTheme.text)
                                Spacer()
                                AdminStatus(state: table.rls ? .good : .bad, text: table.rls ? "On" : "Off")
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
                .frame(width: 320)
            }
            AdminPanel(title: "Accounts to look at", subtitle: "Unconfirmed emails and accounts that never signed in") {
                let flagged = data.users.filter { !$0.confirmed || $0.lastSeen == nil }
                if flagged.isEmpty { AdminStatus(state: .good, text: "None") }
                VStack(spacing: 0) {
                    ForEach(Array(flagged.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { AdminDivider() }
                        HStack {
                            Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text([user.confirmed ? nil : "unconfirmed", user.lastSeen == nil ? "never signed in" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.appFont(size: 11)).foregroundColor(AdminTheme.amber)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }
}

// MARK: - Admin Settings

struct AdminSettingsPage: View {
    let data: AdminData
    @Binding var autoRefresh: Bool
    @Binding var range: AdminRange
    @State private var exportResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminBentoRow {
                AdminPanel(title: "Console", subtitle: "Saved on this Mac") {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live refresh, every second").font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white)
                                Text("While the console is open and Locken is in front").font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $autoRefresh)
                                .toggleStyle(GlassSwitchToggleStyle())
                                .accessibilityLabel("Live refresh every second")
                        }
                        .padding(.vertical, 8)
                        AdminDivider()
                        HStack {
                            Text("Default time window").font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white)
                            Spacer()
                            AdminSegmented(options: AdminRange.allCases, selection: $range) { $0.label }
                        }
                        .padding(.vertical, 8)
                    }
                }
                AdminPanel(title: "Export", subtitle: "A CSV of every account and its activity") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: exportCSV) {
                            Label("Export accounts…", systemImage: "square.and.arrow.down")
                                .font(.appFont(size: 12, weight: .semibold))
                                .foregroundColor(AdminTheme.amber)
                        }
                        .buttonStyle(.plain)
                        if let exportResult {
                            Text(exportResult).font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                        }
                        AdminEmpty(text: "Contains email addresses. Keep the file private.")
                    }
                }
                .frame(width: 320)
            }
            AdminPanel(title: "Admin accounts", subtitle: "Only these can open the console. The server checks on every request.") {
                VStack(spacing: 0) {
                    let admins = data.users.filter(\.isAdmin)
                    ForEach(Array(admins.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { AdminDivider() }
                        HStack {
                            Text(user.email).font(.appFont(size: 12)).foregroundColor(AdminTheme.text)
                            Spacer()
                            Text("last seen \(AdminFormat.relative(user.lastSeen))").font(.appFont(size: 11)).foregroundColor(AdminTheme.muted)
                        }
                        .padding(.vertical, 7)
                    }
                    AdminDivider()
                    AdminEmpty(text: "To add or remove an admin, change the public.admins table in Supabase. It can't be changed from the app, on purpose.")
                        .padding(.top, 8)
                }
            }
            AdminPanel(title: "How the numbers work", subtitle: "Everything comes from data Supabase already keeps; the app sends no tracking") {
                VStack(alignment: .leading, spacing: 0) {
                    explain("Active", "An account is active on a day when the app refreshed its sign-in that day (it does this while open).")
                    AdminDivider()
                    explain("App activity", "The number of those refreshes. It rises with how long Locken stays open.")
                    AdminDivider()
                    explain("Sign-ins", "New sessions started on a Mac (signing in, or a new Mac).")
                    AdminDivider()
                    explain("Build", "Read from the app version each Mac reports when it signs in.")
                    AdminDivider()
                    explain("Comparisons", "Each period is compared with the same number of days just before it.")
                    AdminDivider()
                    explain("Health", "The update server and database are timed by the admin function on each refresh.")
                }
            }
        }
    }

    private func explain(_ term: String, _ meaning: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(term).font(.appFont(size: 12, weight: .semibold)).foregroundColor(.white).frame(width: 110, alignment: .leading)
            Text(meaning).font(.appFont(size: 12)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "locken-accounts-\(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func field(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let iso = ISO8601DateFormatter()
        var lines = ["email,sign_in,confirmed,joined,last_seen,days_used,sessions,build,two_factor,admin"]
        for user in data.users {
            lines.append([
                field(user.email), user.provider, user.confirmed ? "yes" : "no",
                user.created.map { iso.string(from: $0) } ?? "", user.lastSeen.map { iso.string(from: $0) } ?? "",
                "\(user.usage?.activeDays ?? 0)", "\(user.usage?.sessions ?? 0)", user.usage?.build ?? "",
                (user.usage?.mfa ?? false) ? "yes" : "no", user.isAdmin ? "yes" : "no",
            ].joined(separator: ","))
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportResult = "Saved \(data.users.count) accounts to \(url.lastPathComponent)."
        } catch {
            exportResult = "Couldn't save the file."
        }
    }
}
