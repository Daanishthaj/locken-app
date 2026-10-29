import Foundation

/// The admin overview's JSON (from the admin-overview edge function), turned into typed values and the series
/// the console's pages chart. Everything here comes from data Supabase already keeps; the app collects nothing new.
struct AdminData {
    struct Usage {
        let activeDays: Int
        let refreshes: Int
        let sessions: Int
        let liveSessions: Int
        let mfa: Bool
        let build: String?
        let lastActive: Date?
        let activeDates: [Date]
    }
    struct User: Identifiable {
        let id: String
        let email: String
        let provider: String
        let confirmed: Bool
        var banned = false
        let created: Date?
        let lastSeen: Date?
        let usage: Usage?
        var isAdmin = false
    }
    struct Feedback { let email: String; let rating: Int?; let message: String; let version: String?; let date: Date? }
    struct Audit { let action: String; let table: String; let account: String?; let date: Date? }
    struct Day { let day: Date; let active: Int; let refreshes: Int; let signups: Int; let signIns: Int }
    struct Build { let build: String; let users: Int }
    struct Method { let provider: String; let accounts: Int; let lastUsed: Date?; let newLast30: Int }
    struct Event: Identifiable {
        enum Kind: String, CaseIterable {
            case signup, confirmed, signin, mfa, feedback, change
            var label: String {
                switch self {
                case .signup: return "Sign-up"
                case .confirmed: return "Email confirmed"
                case .signin: return "Sign-in"
                case .mfa: return "Two-factor on"
                case .feedback: return "Feedback"
                case .change: return "Data change"
                }
            }
        }
        let id: Int
        let date: Date
        let kind: Kind
        let email: String?
        let detail: String?
    }
    struct Database { var sizeMB = 0.0; var profiles = 0; var feedback = 0; var auditEntries = 0; var focusSessions = 0; var waitlist = 0 }
    struct Security { var tables: [(name: String, rls: Bool)] = []; var exposedFunctions: [String] = []; var adminIDs: [String] = [] }
    struct Endpoint { var reachable = false; var ms: Int?; var status: Int? }
    struct Bucket { let label: String; let count: Int }

    let users: [User]
    let feedback: [Feedback]
    let audit: [Audit]
    let liveVersion: String?
    let liveBuild: Int?
    let liveNotes: String?
    let maintenanceMode: Bool
    let generatedAt: Date?

    // From admin_analytics() on the server.
    let daily: [Day]
    let builds: [Build]
    let methods: [Method]
    let events: [Event]
    let database: Database
    let security: Security
    let weeklyActive: Int
    let monthlyActive: Int
    let returningUsers: Int
    let oneDayUsers: Int
    let liveSessions: Int
    let twoFactorUsers: Int
    let unconfirmed: Int

    // Health checks made by the edge function on each refresh.
    let updateServer: Endpoint
    let databaseMs: Int?
    let databaseOK: Bool

    var isEmpty: Bool { users.isEmpty && daily.isEmpty }

    init(_ json: [String: Any]) {
        let analytics = json["analytics"] as? [String: Any] ?? [:]
        let securityJSON = analytics["security"] as? [String: Any] ?? [:]
        let adminIDs = Set((securityJSON["admins"] as? [String]) ?? [])

        var usageByID: [String: Usage] = [:]
        for row in analytics["perUser"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? String else { continue }
            usageByID[id] = Usage(
                activeDays: Self.int(row["activeDays"]), refreshes: Self.int(row["refreshes"]),
                sessions: Self.int(row["sessions"]), liveSessions: Self.int(row["liveSessions"]),
                mfa: (row["mfa"] as? Bool) ?? false, build: row["build"] as? String,
                lastActive: Self.day(row["lastActive"]),
                activeDates: ((row["activeDates"] as? [Any]) ?? []).compactMap { Self.day($0) }.sorted()
            )
        }

        users = (json["users"] as? [[String: Any]] ?? []).map {
            let id = $0["id"] as? String ?? UUID().uuidString
            return User(id: id, email: $0["email"] as? String ?? "",
                        provider: $0["provider"] as? String ?? "email",
                        confirmed: ($0["confirmed"] as? Bool) ?? true,
                        banned: ($0["banned"] as? Bool) ?? false,
                        created: Self.date($0["createdAt"]), lastSeen: Self.date($0["lastSignInAt"]),
                        usage: usageByID[id], isAdmin: adminIDs.contains(id))
        }
        let emailFor = Dictionary(users.map { ($0.id, $0.email) }, uniquingKeysWith: { first, _ in first })

        feedback = (json["feedback"] as? [[String: Any]] ?? []).map {
            Feedback(email: $0["email"] as? String ?? "", rating: $0["rating"] as? Int, message: $0["message"] as? String ?? "",
                     version: $0["appVersion"] as? String, date: Self.date($0["createdAt"]))
        }
        audit = (json["audit"] as? [[String: Any]] ?? []).map {
            Audit(action: $0["action"] as? String ?? "", table: $0["table"] as? String ?? "",
                  account: $0["account"] as? String, date: Self.date($0["occurredAt"]))
        }
        let live = json["liveVersion"] as? [String: Any]
        liveVersion = live?["version"] as? String
        liveBuild = live.map { Self.int($0["build"]) }.flatMap { $0 > 0 ? $0 : nil }
        liveNotes = live?["notes"] as? String
        maintenanceMode = (live?["maintenanceMode"] as? Bool) ?? false
        generatedAt = Self.date(json["generatedAt"])

        // The server counts days in UTC, which can run a day ahead of this Mac; stop at the local today.
        let localToday = Calendar.current.startOfDay(for: Date())
        daily = (analytics["daily"] as? [[String: Any]] ?? []).compactMap {
            guard let day = Self.day($0["day"]), day <= localToday else { return nil }
            return Day(day: day, active: Self.int($0["activeUsers"]), refreshes: Self.int($0["refreshes"]),
                       signups: Self.int($0["signups"]), signIns: Self.int($0["signIns"]))
        }
        builds = (analytics["builds"] as? [[String: Any]] ?? []).compactMap {
            guard let build = $0["build"] as? String else { return nil }
            return Build(build: build, users: Self.int($0["users"]))
        }
        methods = (analytics["signInMethods"] as? [[String: Any]] ?? []).map {
            Method(provider: $0["provider"] as? String ?? "", accounts: Self.int($0["accounts"]),
                   lastUsed: Self.date($0["lastUsed"]), newLast30: Self.int($0["newLast30"]))
        }
        events = (analytics["events"] as? [[String: Any]] ?? []).enumerated().compactMap { index, row in
            guard let date = Self.date(row["at"]), let kind = Event.Kind(rawValue: row["kind"] as? String ?? "") else { return nil }
            let email = (row["userId"] as? String).flatMap { emailFor[$0] }
            return Event(id: index, date: date, kind: kind, email: email, detail: row["detail"] as? String)
        }
        let db = analytics["database"] as? [String: Any] ?? [:]
        database = Database(sizeMB: (db["sizeMB"] as? NSNumber)?.doubleValue ?? 0, profiles: Self.int(db["profiles"]),
                            feedback: Self.int(db["feedback"]), auditEntries: Self.int(db["auditEntries"]),
                            focusSessions: Self.int(db["focusSessions"]), waitlist: Self.int(db["waitlist"]))
        security = Security(
            tables: (securityJSON["tables"] as? [[String: Any]] ?? []).map { ($0["table"] as? String ?? "", ($0["rls"] as? Bool) ?? false) },
            exposedFunctions: securityJSON["exposedFunctions"] as? [String] ?? [],
            adminIDs: Array(adminIDs)
        )
        weeklyActive = Self.int(analytics["weeklyActive"])
        monthlyActive = Self.int(analytics["monthlyActive"])
        returningUsers = Self.int(analytics["returningUsers"])
        oneDayUsers = Self.int(analytics["oneDayUsers"])
        liveSessions = Self.int(analytics["liveSessions"])
        twoFactorUsers = Self.int(analytics["twoFactorUsers"])
        unconfirmed = Self.int(analytics["unconfirmed"])

        let server = json["updateServer"] as? [String: Any] ?? [:]
        updateServer = Endpoint(reachable: (server["reachable"] as? Bool) ?? false,
                                ms: (server["ms"] as? NSNumber)?.intValue, status: (server["status"] as? NSNumber)?.intValue)
        let databaseJSON = json["database"] as? [String: Any] ?? [:]
        databaseMs = (databaseJSON["ms"] as? NSNumber)?.intValue
        databaseOK = (databaseJSON["ok"] as? Bool) ?? !analytics.isEmpty
    }

    // MARK: Parsing

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) ?? 0 }
        return 0
    }

    /// A plain "yyyy-MM-dd" day from Postgres, in the Mac's own time zone so it lines up with chart days.
    static func day(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }

    /// Supabase timestamps come with up to 6 fractional digits; drop them so the standard parser accepts them.
    static func date(_ value: Any?) -> Date? {
        guard var text = value as? String, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: " ", with: "T")
        if let dot = text.firstIndex(of: ".") {
            let rest = text[dot...]
            let zone = rest.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }).map { String(rest[$0...]) } ?? "Z"
            text = String(text[..<dot]) + zone
        }
        if text.hasSuffix("+00") { text += ":00" }
        return ISO8601DateFormatter().date(from: text)
    }

    // MARK: Periods

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    /// The last `days` days of the daily series (oldest first). `offset` shifts back by whole periods.
    func days(_ days: Int, offset: Int = 0) -> [Day] {
        let end = daily.count - offset * days
        let start = max(0, end - days)
        guard end > 0, start < end else { return [] }
        return Array(daily[start..<end])
    }

    /// Distinct people active in the last `days` days, or in the period before that with `offset: 1`.
    func activePeople(days: Int, offset: Int = 0) -> Int {
        guard let upper = calendar.date(byAdding: .day, value: -offset * days, to: today),
              let lower = calendar.date(byAdding: .day, value: -days + 1, to: upper) else { return 0 }
        return users.filter { user in
            (user.usage?.activeDates ?? []).contains { $0 >= lower && $0 <= upper }
        }.count
    }

    func signups(days: Int, offset: Int = 0) -> Int { self.days(days, offset: offset).reduce(0) { $0 + $1.signups } }
    func signIns(days: Int, offset: Int = 0) -> Int { self.days(days, offset: offset).reduce(0) { $0 + $1.signIns } }
    func refreshes(days: Int, offset: Int = 0) -> Int { self.days(days, offset: offset).reduce(0) { $0 + $1.refreshes } }
    var activeToday: Int { daily.last?.active ?? 0 }

    func averageDailyActive(days: Int) -> Double {
        let recent = self.days(days)
        return recent.isEmpty ? 0 : Double(recent.reduce(0) { $0 + $1.active }) / Double(recent.count)
    }

    /// Total accounts at the end of each day in the period.
    func cumulativeAccounts(days: Int) -> [(day: Date, count: Int)] {
        let created = users.compactMap(\.created).sorted()
        return self.days(days).map { point in
            let next = calendar.date(byAdding: .day, value: 1, to: point.day) ?? point.day
            return (point.day, created.filter { $0 < next }.count)
        }
    }

    // MARK: People

    var neverSignedIn: Int { users.filter { $0.lastSeen == nil }.count }
    var google: Int { users.filter { $0.provider == "google" }.count }
    var ratings: [Int] { feedback.compactMap(\.rating) }
    var averageRating: Double? { ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count) }
    var usersWithBuild: Int { builds.reduce(0) { $0 + $1.users } }
    var usersOnLiveBuild: Int { liveBuild.map { live in builds.filter { $0.build == "\(live)" }.reduce(0) { $0 + $1.users } } ?? 0 }
    var usersOnOldBuilds: [User] {
        guard let live = liveBuild else { return [] }
        return users.filter { user in user.usage?.build.flatMap(Int.init).map { $0 < live } ?? false }
    }
    var manySessionUsers: [User] { users.filter { ($0.usage?.liveSessions ?? 0) > 5 } }
    func newUsers(days: Int) -> [User] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return users.filter { ($0.created ?? .distantPast) > cutoff }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    func mostActive(limit: Int) -> [User] {
        Array(users.filter { ($0.usage?.activeDays ?? 0) > 0 }
            .sorted { ($0.usage?.activeDays ?? 0) > ($1.usage?.activeDays ?? 0) }
            .prefix(limit))
    }

    func recency() -> [Bucket] {
        let now = Date()
        func count(_ test: (TimeInterval) -> Bool) -> Int { users.filter { $0.lastSeen.map { test(now.timeIntervalSince($0)) } ?? false }.count }
        return [
            Bucket(label: "Today", count: count { $0 <= 86400 }),
            Bucket(label: "This week", count: count { $0 > 86400 && $0 <= 7 * 86400 }),
            Bucket(label: "This month", count: count { $0 > 7 * 86400 && $0 <= 30 * 86400 }),
            Bucket(label: "Longer ago", count: count { $0 > 30 * 86400 }),
            Bucket(label: "Never", count: neverSignedIn),
        ]
    }

    /// How many days each account has used Locken, grouped.
    func activeDayGroups() -> [Bucket] {
        let counts = users.map { $0.usage?.activeDays ?? 0 }
        return [
            Bucket(label: "Never used", count: counts.filter { $0 == 0 }.count),
            Bucket(label: "1 day", count: counts.filter { $0 == 1 }.count),
            Bucket(label: "2–4 days", count: counts.filter { (2...4).contains($0) }.count),
            Bucket(label: "5–9 days", count: counts.filter { (5...9).contains($0) }.count),
            Bucket(label: "10+ days", count: counts.filter { $0 >= 10 }.count),
        ]
    }

    func ratingCounts() -> [(stars: Int, count: Int)] {
        (1...5).map { stars in (stars, ratings.filter { $0 == stars }.count) }
    }

    // MARK: Retention

    struct Cohort: Identifiable {
        let id: Date
        let size: Int
        /// Share of the cohort active in each week after signing up; nil for weeks that haven't happened yet.
        let weeks: [Double?]
    }

    /// People grouped by the week they signed up (last `count` weeks), and how many came back in each later week.
    func cohorts(count: Int = 8, weeksAfter: Int = 4) -> [Cohort] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<count).reversed().compactMap { back -> Cohort? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let members = users.filter { ($0.created ?? .distantPast) >= start && ($0.created ?? .distantFuture) < end }
            let weeks: [Double?] = (0...weeksAfter).map { week in
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: start),
                      let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart),
                      weekStart <= Date(), !members.isEmpty else { return nil }
                let active = members.filter { member in
                    (member.usage?.activeDates ?? []).contains { $0 >= calendar.startOfDay(for: weekStart) && $0 < weekEnd }
                }.count
                return Double(active) / Double(members.count)
            }
            return Cohort(id: start, size: members.count, weeks: weeks)
        }
    }

    // MARK: Attention

    struct Alert: Identifiable {
        enum Level: Int { case critical = 0, warning = 1, info = 2 }
        let id: String
        let level: Level
        let title: String
        let detail: String
        let page: AdminPage
    }

    /// Things worth a look right now, most serious first.
    var alerts: [Alert] {
        var list: [Alert] = []
        if !updateServer.reachable {
            list.append(Alert(id: "update", level: .critical, title: "Update server isn't answering",
                              detail: "locken-app.vercel.app/version.json didn't respond, so nobody can update.", page: .health))
        }
        if !databaseOK {
            list.append(Alert(id: "db", level: .critical, title: "Analytics query failed",
                              detail: "admin_analytics() returned an error; numbers below may be missing.", page: .health))
        }
        let unprotected = security.tables.filter { !$0.rls }.map(\.name)
        if !unprotected.isEmpty {
            list.append(Alert(id: "rls", level: .critical, title: "Row Level Security is off",
                              detail: "Turn it on for: \(unprotected.joined(separator: ", ")).", page: .security))
        }
        if !security.exposedFunctions.isEmpty {
            list.append(Alert(id: "fn", level: .critical, title: "Server functions open to app users",
                              detail: security.exposedFunctions.joined(separator: ", "), page: .security))
        }
        if maintenanceMode {
            list.append(Alert(id: "maint", level: .warning, title: "Maintenance mode is on",
                              detail: "The app tells everyone Locken is under maintenance.", page: .health))
        }
        if !manySessionUsers.isEmpty {
            list.append(Alert(id: "sessions", level: .warning, title: "\(manySessionUsers.count) account(s) signed in on more than 5 Macs",
                              detail: "Could be shared accounts. Check them in Security.", page: .security))
        }
        let lowRatings = feedback.filter { ($0.rating ?? 5) <= 2 && ($0.date ?? .distantPast) > Date().addingTimeInterval(-7 * 86400) }
        if !lowRatings.isEmpty {
            list.append(Alert(id: "ratings", level: .warning, title: "\(lowRatings.count) low rating(s) this week",
                              detail: "Read what they said in Analytics › Feedback.", page: .analytics))
        }
        if database.sizeMB > 400 {
            list.append(Alert(id: "dbsize", level: .warning, title: "Database is \(Int(database.sizeMB)) MB of 500 MB",
                              detail: "The free plan pauses writes at 500 MB.", page: .usage))
        }
        if !usersOnOldBuilds.isEmpty {
            list.append(Alert(id: "builds", level: .info, title: "\(usersOnOldBuilds.count) of \(usersWithBuild) people haven't updated",
                              detail: "They last signed in on an older build.", page: .health))
        }
        if unconfirmed > 0 {
            list.append(Alert(id: "unconfirmed", level: .info, title: "\(unconfirmed) email(s) never confirmed",
                              detail: "Sign-up started but the code wasn't entered (or the address bounced).", page: .users))
        }
        if neverSignedIn > 0 {
            list.append(Alert(id: "never", level: .info, title: "\(neverSignedIn) account(s) never signed in",
                              detail: "Made an account, never opened the app with it.", page: .users))
        }
        return list.sorted { $0.level.rawValue < $1.level.rawValue }
    }
}
