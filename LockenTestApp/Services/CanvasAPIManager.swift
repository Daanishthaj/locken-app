import Foundation
import Combine

public struct CanvasAssignment: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let dueDate: Date?
    public let htmlURL: URL?
    /// YouTube videos linked in the assignment's description; they stay open during its focus session.
    public var videoIDs: [String] = []
    /// What Canvas says the assignment is, as plain text (see `CanvasAPIManager.plainText`); empty when Canvas sent none.
    public var details = ""
    /// Points it's worth, when Canvas says.
    public var points: Double?
}

/// Links a student's Canvas account and loads their pending assignments, either through the Canvas LMS
/// REST API (school address + personal access token) or through the Canvas calendar feed (.ics link).
///
/// With a token it reads the to-do list (`GET /api/v1/users/self/todo`) plus every active course's
/// assignments due from now on that haven't been submitted (`GET /api/v1/courses/:course_id/assignments`).
/// The token and feed link are stored in the macOS Keychain, never in UserDefaults or on disk.
///
/// A third way to link is Google Classroom (`GoogleClassroom`): Google's sign-in, then the same list of assignments.
/// Only one way is linked at a time.
@MainActor
public final class CanvasAPIManager: ObservableObject {
    public static let shared = CanvasAPIManager()

    public enum LinkMethod: String {
        case accessToken
        case calendarFeed
        case googleClassroom
    }

    /// Pending assignments, minus any the student checked off by hand.
    @Published public private(set) var assignments: [CanvasAssignment] = []
    /// Everything Canvas returned, before hand check-offs are hidden.
    private var fetchedAssignments: [CanvasAssignment] = [] { didSet { applyCheckOffs() } }
    /// Assignments checked off in Locken (for work that's handed in on paper or in person). Saved per account.
    @Published public private(set) var checkedOffIDs: Set<String> = [] { didSet { applyCheckOffs() } }
    /// The last one checked off, so it can be undone.
    @Published public private(set) var lastCheckedOff: CanvasAssignment?
    @Published public private(set) var linkMethod: LinkMethod?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastSynced: Date?

    public var isLinked: Bool { linkMethod != nil }

    // Everything below is per account (suffixed with `AccountScope.suffix`), so accounts never share a Canvas link.
    private enum DefaultsKey {
        static let linkMethodBase = "canvas.linkMethod"
        static let hostBase = "canvas.host"
        static let checkedOffBase = "canvas.checkedOff"
        @MainActor static var checkedOff: String { checkedOffBase + AccountScope.suffix }
        @MainActor static var linkMethod: String { linkMethodBase + AccountScope.suffix }
        @MainActor static var host: String { hostBase + AccountScope.suffix }
    }

    /// "-v2" since 2.0.3: items from earlier builds made macOS ask for the Mac password, so they are never read.
    private static let keychainService = "com.locken.LockenTestApp.canvas-v2"

    private enum KeychainAccount {
        static let accessTokenBase = "canvas.accessToken"
        static let calendarFeedURLBase = "canvas.calendarFeedURL"
        static let classroomRefreshTokenBase = "classroom.refreshToken"
        @MainActor static var classroomRefreshToken: String { classroomRefreshTokenBase + AccountScope.suffix }
        @MainActor static var accessToken: String { accessTokenBase + AccountScope.suffix }
        @MainActor static var calendarFeedURL: String { calendarFeedURLBase + AccountScope.suffix }
    }

    private enum Source {
        case accessToken(host: String, token: String)
        case calendarFeed(URL)
        case googleClassroom(refreshToken: String)
    }

    /// The name shown in messages.
    private var serviceName: String { linkMethod == .googleClassroom ? "Google Classroom" : "Canvas" }

    private init() {}

    /// Loads the signed-in account's Canvas link.
    public func activateAccount() {
        #if DEBUG
        GoogleClassroom.selfCheck()
        Self.selfCheckDescriptions()
        #endif
        AccountScope.adoptLegacyKeychainItem(service: Self.keychainService, account: KeychainAccount.accessTokenBase)
        AccountScope.adoptLegacyKeychainItem(service: Self.keychainService, account: KeychainAccount.calendarFeedURLBase)
        AccountScope.adoptLegacyDefault(DefaultsKey.linkMethodBase)
        AccountScope.adoptLegacyDefault(DefaultsKey.hostBase)
        linkMethod = UserDefaults.standard.string(forKey: DefaultsKey.linkMethod).flatMap(LinkMethod.init(rawValue:))
        checkedOffIDs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.checkedOff) ?? [])
        lastCheckedOff = nil
        fetchedAssignments = []
        errorMessage = nil
        lastSynced = nil
    }

    @discardableResult
    public func link(schoolAddress: String, accessToken: String) async -> Bool {
        guard let host = Self.normalizedHost(schoolAddress) else {
            errorMessage = "Enter your school's Canvas address, for example school.instructure.com."
            return false
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Paste your Canvas access token."
            return false
        }
        guard await load(from: .accessToken(host: host, token: token)) else { return false }

        KeychainStore.set(token, service: Self.keychainService, account: KeychainAccount.accessToken)
        KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.calendarFeedURL)
        UserDefaults.standard.set(host, forKey: DefaultsKey.host)
        setLinkMethod(.accessToken)
        return true
    }

    @discardableResult
    public func link(calendarFeedURL: String) async -> Bool {
        guard let url = Self.normalizedFeedURL(calendarFeedURL) else {
            errorMessage = "Paste the calendar feed link from Canvas (Calendar → Calendar Feed)."
            return false
        }
        guard await load(from: .calendarFeed(url)) else { return false }

        KeychainStore.set(url.absoluteString, service: Self.keychainService, account: KeychainAccount.calendarFeedURL)
        KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.accessToken)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.host)
        setLinkMethod(.calendarFeed)
        return true
    }

    /// Links Google Classroom: Google's sign-in sheet, then the first load of assignments.
    @discardableResult
    public func linkGoogleClassroom() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tokens = try await GoogleClassroom.signIn()
            guard let refresh = tokens.refreshToken else { throw GoogleClassroom.Failure.noRefreshToken }
            // The link is only saved once the first load works.
            let previous = linkMethod
            linkMethod = .googleClassroom
            guard await load(from: .googleClassroom(refreshToken: refresh)) else {
                linkMethod = previous
                return false
            }
            KeychainStore.set(refresh, service: Self.keychainService, account: KeychainAccount.classroomRefreshToken)
            KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.accessToken)
            KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.calendarFeedURL)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.host)
            setLinkMethod(.googleClassroom)
            return true
        } catch let failure as GoogleClassroom.Failure {
            if case .cancelled = failure { return false }
            errorMessage = Self.classroomMessage(failure)
            return false
        } catch {
            errorMessage = Self.message(for: error, service: "Google Classroom")
            return false
        }
    }

    public func refresh() async {
        guard let source = storedSource() else {
            if isLinked { errorMessage = "\(serviceName) sign-in details are missing. Unlink and link it again." }
            return
        }
        _ = await load(from: source)
    }

    public func unlink() {
        // Google is told to forget the grant, then the saved sign-in goes.
        if let refresh = KeychainStore.get(service: Self.keychainService, account: KeychainAccount.classroomRefreshToken) {
            Task { await GoogleClassroom.revoke(refreshToken: refresh) }
        }
        KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.classroomRefreshToken)
        KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.accessToken)
        KeychainStore.delete(service: Self.keychainService, account: KeychainAccount.calendarFeedURL)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.host)
        setLinkMethod(nil)
        fetchedAssignments = []
        lastCheckedOff = nil
        errorMessage = nil
        lastSynced = nil
    }

    /// Marks an assignment done in Locken only (nothing is sent to Canvas), and hides it from the pending lists.
    public func checkOff(_ assignment: CanvasAssignment) {
        checkedOffIDs.insert(assignment.id)
        lastCheckedOff = assignment
        saveCheckOffs()
    }

    public func undoCheckOff() {
        guard let assignment = lastCheckedOff else { return }
        checkedOffIDs.remove(assignment.id)
        lastCheckedOff = nil
        saveCheckOffs()
    }

    /// Brings back every assignment checked off by hand.
    public func restoreCheckedOff() {
        checkedOffIDs = []
        lastCheckedOff = nil
        saveCheckOffs()
    }

    /// How many of Canvas's current assignments are hidden because they were checked off.
    public var checkedOffCount: Int { fetchedAssignments.filter { checkedOffIDs.contains($0.id) }.count }

    private func applyCheckOffs() {
        assignments = fetchedAssignments.filter { !checkedOffIDs.contains($0.id) }
    }

    private func saveCheckOffs() {
        // Kept small: only the most recent 500 check-offs are remembered.
        UserDefaults.standard.set(Array(checkedOffIDs.sorted().suffix(500)), forKey: DefaultsKey.checkedOff)
    }

    public func clearError() {
        errorMessage = nil
    }

    private func setLinkMethod(_ method: LinkMethod?) {
        linkMethod = method
        UserDefaults.standard.set(method?.rawValue, forKey: DefaultsKey.linkMethod)
    }

    private func storedSource() -> Source? {
        switch linkMethod {
        case .accessToken:
            guard let host = UserDefaults.standard.string(forKey: DefaultsKey.host),
                  let token = KeychainStore.get(service: Self.keychainService, account: KeychainAccount.accessToken) else { return nil }
            return .accessToken(host: host, token: token)
        case .calendarFeed:
            guard let raw = KeychainStore.get(service: Self.keychainService, account: KeychainAccount.calendarFeedURL),
                  let url = URL(string: raw) else { return nil }
            return .calendarFeed(url)
        case .googleClassroom:
            guard let refresh = KeychainStore.get(service: Self.keychainService, account: KeychainAccount.classroomRefreshToken) else { return nil }
            return .googleClassroom(refreshToken: refresh)
        case nil:
            return nil
        }
    }

    private func load(from source: Source) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let parsed: [CanvasAssignment]
            switch source {
            case .accessToken(let host, let token):
                parsed = try await Self.fetchPendingAssignments(client: CanvasClient(host: host, token: token))
            case .calendarFeed(let url):
                parsed = try await Self.fetchCalendarFeed(url)
            case .googleClassroom(let refreshToken):
                parsed = try await GoogleClassroom.fetchAssignments(accessToken: GoogleClassroom.accessToken(refreshToken: refreshToken))
            }
            fetchedAssignments = Self.upcoming(parsed, now: Date())
            lastSynced = Date()
            return true
        } catch let failure as GoogleClassroom.Failure {
            errorMessage = Self.classroomMessage(failure)
            return false
        } catch let error as CanvasError {
            switch error {
            case .status(let status): errorMessage = Self.message(forStatus: status, source: source)
            case .unreadable: errorMessage = "Canvas sent a response Locken couldn't read."
            case .notACalendarFeed: errorMessage = "That link didn't return a Canvas calendar feed."
            case .badAddress: errorMessage = "That Canvas address isn't valid."
            }
            return false
        } catch {
            errorMessage = Self.message(for: error, service: serviceName)
            return false
        }
    }

    /// What to tell the student when Google Classroom didn't work; never Google's own text.
    private static func classroomMessage(_ failure: GoogleClassroom.Failure) -> String {
        switch failure {
        case .notSetUp: return "Google Classroom isn't set up in this version of Locken yet."
        case .cancelled: return ""
        case .signInFailed, .unreadable, .noRefreshToken: return "Google sign-in didn't finish. Try again."
        case .blockedBySchool: return "Your school doesn't let students use apps like Locken with Google Classroom. Ask your school, or use Canvas instead."
        case .signInAgain: return "Google needs you to sign in again. Unlink and link Google Classroom again."
        case .status(401), .status(403): return "Google Classroom didn't allow that. Unlink and link it again, or ask your school if apps can read Classroom."
        case .status(429): return "Google Classroom is busy right now. Try again in a minute."
        case .status(500...599): return "Google Classroom is having problems right now. Try again later."
        case .status: return "Couldn't load your assignments from Google Classroom. Try again later."
        }
    }

    enum CanvasError: Error {
        case status(Int)
        case unreadable
        case notACalendarFeed
        case badAddress
    }

    /// Authenticated GETs against one Canvas host, following `Link: <…>; rel="next"` pagination.
    struct CanvasClient: Sendable {
        let host: String
        let token: String

        func getPages(_ path: String, query: [(String, String)], maxPages: Int = 10) async throws -> [Data] {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
            guard var next = components.url else { throw CanvasError.badAddress }

            var pages: [Data] = []
            for _ in 0..<maxPages {
                var request = URLRequest(url: next)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (data, response) = try await SecureNetwork.session.data(for: request)
                let http = response as? HTTPURLResponse
                guard http?.statusCode == 200 else { throw CanvasError.status(http?.statusCode ?? 0) }
                pages.append(data)

                // Only follow links on the same host, so the token is never sent anywhere else.
                guard let link = http?.value(forHTTPHeaderField: "Link"),
                      let nextURL = Self.nextPageURL(fromLinkHeader: link),
                      nextURL.host?.lowercased() == host else { break }
                next = nextURL
            }
            return pages
        }

        static func nextPageURL(fromLinkHeader header: String) -> URL? {
            for part in header.split(separator: ",") where part.contains("rel=\"next\"") {
                guard let open = part.firstIndex(of: "<"), let close = part.firstIndex(of: ">"), open < close else { continue }
                return URL(string: String(part[part.index(after: open)..<close]))
            }
            return nil
        }
    }

    /// The to-do list is required (it also proves the token works); per-course lists are best-effort,
    /// since some courses restrict their assignment list for students.
    nonisolated static func fetchPendingAssignments(client: CanvasClient) async throws -> [CanvasAssignment] {
        var byID: [String: CanvasAssignment] = [:]
        for page in try await client.getPages("/api/v1/users/self/todo", query: [("per_page", "50")]) {
            guard let items = parseTodo(page) else { throw CanvasError.unreadable }
            for item in items { byID[item.id] = item }
        }

        guard let coursePages = try? await client.getPages(
            "/api/v1/courses",
            query: [("enrollment_state", "active"), ("per_page", "100")]
        ) else { return Array(byID.values) }
        let courses = coursePages.flatMap(parseCourses)

        await withTaskGroup(of: [CanvasAssignment].self) { group in
            for course in courses {
                group.addTask {
                    let pages = try? await client.getPages(
                        "/api/v1/courses/\(course.id)/assignments",
                        query: [("bucket", "future"), ("include[]", "submission"), ("order_by", "due_at"), ("per_page", "100")]
                    )
                    return (pages ?? []).flatMap { parseCourseAssignments($0, courseName: course.name) }
                }
            }
            for await assignments in group {
                for assignment in assignments where byID[assignment.id] == nil {
                    byID[assignment.id] = assignment
                }
            }
        }
        return Array(byID.values)
    }

    nonisolated static func fetchCalendarFeed(_ url: URL) async throws -> [CanvasAssignment] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await SecureNetwork.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CanvasError.status(status) }
        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
            throw CanvasError.notACalendarFeed
        }
        return parseCalendarFeed(text)
    }

    private static func message(forStatus status: Int, source: Source) -> String {
        switch (status, source) {
        case (401, _):
            return "Canvas rejected the access token. Create a new one in Canvas → Account → Settings."
        case (403, _):
            return "Canvas refused access. Your school may not allow access tokens — try the calendar feed instead."
        case (404, .calendarFeed):
            return "Canvas couldn't find that calendar feed. Copy the link again from Calendar → Calendar Feed."
        case (404, .accessToken):
            return "No Canvas site found at that address. Check your school's Canvas URL."
        case (429, _):
            return "Canvas is busy right now. Try again in a minute."
        case (500...599, _):
            return "Your school's Canvas is having problems right now. Try again later."
        default:
            return "Couldn't load your assignments from Canvas. Try again later."
        }
    }

    /// What to show when Canvas couldn't be reached at all; never the raw system error.
    private static func message(for error: Error, service: String) -> String {
        guard let urlError = error as? URLError else { return "Couldn't reach \(service). Try again." }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You're offline. Connect to the internet and try again."
        case .timedOut:
            return "\(service) took too long to answer. Try again in a moment."
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return service == "Canvas" ? "Couldn't find that Canvas address. Check your school's Canvas URL." : "Couldn't reach \(service). Try again."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "Couldn't make a secure connection to that address."
        default:
            return "Couldn't reach \(service). Try again."
        }
    }

    // MARK: - Input normalization

    nonisolated static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."),
              text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return text
    }

    nonisolated static func normalizedFeedURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Canvas offers the feed as webcal:// for calendar apps; it's the same resource over https.
        for prefix in ["webcal://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text = "https://" + text.dropFirst(prefix.count)
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    // MARK: - Parsing

    /// Keeps assignments due within the last day or later (so something that just passed is still visible), soonest first; undated ones last.
    nonisolated static func upcoming(_ assignments: [CanvasAssignment], now: Date) -> [CanvasAssignment] {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        return assignments
            .filter { ($0.dueDate ?? .distantFuture) >= cutoff }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Parses `GET /api/v1/users/self/todo`. Returns nil if the body isn't a to-do list.
    nonisolated static func parseTodo(_ data: Data) -> [CanvasAssignment]? {
        struct TodoItem: Decodable {
            struct Assignment: Decodable {
                let id: Int
                let name: String
                let dueAt: String?
                let htmlUrl: String?
                let description: String?
                let pointsPossible: Double?
            }
            let assignment: Assignment?
            let contextName: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let items = try? decoder.decode([TodoItem].self, from: data) else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        var seen = Set<Int>()
        return items.compactMap { item in
            guard let assignment = item.assignment, seen.insert(assignment.id).inserted else { return nil }
            let due = assignment.dueAt.flatMap { plain.date(from: $0) ?? withFraction.date(from: $0) }
            return CanvasAssignment(
                id: "api-\(assignment.id)",
                title: assignment.name,
                courseName: item.contextName ?? "",
                dueDate: due,
                htmlURL: assignment.htmlUrl.flatMap(URL.init(string:)),
                videoIDs: AppBlockingManager.youTubeVideoIDs(in: assignment.description ?? ""),
                details: plainText(fromHTML: assignment.description ?? ""),
                points: assignment.pointsPossible
            )
        }
    }

    /// Parses `GET /api/v1/courses`, skipping courses whose details are hidden (access restricted by date).
    nonisolated static func parseCourses(_ data: Data) -> [(id: Int, name: String)] {
        struct Course: Decodable {
            let id: Int
            let name: String?
            let courseCode: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let courses = try? decoder.decode([Course].self, from: data) else { return [] }
        return courses.compactMap { course in
            guard let name = course.name ?? course.courseCode else { return nil }
            return (course.id, name)
        }
    }

    /// Parses `GET /api/v1/courses/:course_id/assignments?include[]=submission`, keeping dated
    /// assignments the student hasn't submitted yet.
    nonisolated static func parseCourseAssignments(_ data: Data, courseName: String) -> [CanvasAssignment] {
        struct Assignment: Decodable {
            struct Submission: Decodable {
                let workflowState: String?
                let submittedAt: String?
            }
            let id: Int
            let name: String
            let dueAt: String?
            let htmlUrl: String?
            let description: String?
            let pointsPossible: Double?
            let submission: Submission?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let items = try? decoder.decode([Assignment].self, from: data) else { return [] }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return items.compactMap { item in
            guard let dueAt = item.dueAt, let due = plain.date(from: dueAt) ?? withFraction.date(from: dueAt) else { return nil }
            if let submission = item.submission {
                guard submission.submittedAt == nil, (submission.workflowState ?? "unsubmitted") == "unsubmitted" else { return nil }
            }
            return CanvasAssignment(
                id: "api-\(item.id)",
                title: item.name,
                courseName: courseName,
                dueDate: due,
                htmlURL: item.htmlUrl.flatMap(URL.init(string:)),
                videoIDs: AppBlockingManager.youTubeVideoIDs(in: item.description ?? ""),
                details: plainText(fromHTML: item.description ?? ""),
                points: item.pointsPossible
            )
        }
    }

    /// Parses a Canvas calendar feed (RFC 5545), keeping only assignment events.
    nonisolated static func parseCalendarFeed(_ ics: String) -> [CanvasAssignment] {
        // Long lines are folded as CRLF + one space or tab; join them back before reading properties.
        let unfolded = ics
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        var results: [CanvasAssignment] = []
        var event: [String: (params: String, value: String)]?

        for rawLine in unfolded.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line == "BEGIN:VEVENT" {
                event = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let properties = event, let assignment = assignment(from: properties) {
                    results.append(assignment)
                }
                event = nil
                continue
            }
            guard event != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].split(separator: ";", maxSplits: 1)
            let name = String(head[0]).uppercased()
            let params = head.count > 1 ? String(head[1]) : ""
            event?[name] = (params, String(line[line.index(after: colon)...]))
        }
        return results
    }

    nonisolated private static func assignment(from properties: [String: (params: String, value: String)]) -> CanvasAssignment? {
        // Canvas marks assignment events with UIDs like "event-assignment-123" (or "-override-"); other events are calendar entries.
        guard let uid = properties["UID"]?.value, uid.contains("assignment"),
              let rawSummary = properties["SUMMARY"]?.value else { return nil }

        let summary = unescapeText(rawSummary)
        var title = summary
        var course = ""
        // Canvas appends the course as " [COURSE CODE]".
        if summary.hasSuffix("]"), let open = summary.range(of: " [", options: .backwards) {
            title = String(summary[..<open.lowerBound])
            course = String(summary[open.upperBound..<summary.index(before: summary.endIndex)])
        }

        let dateProperty = properties["DTSTART"] ?? properties["DTEND"]
        return CanvasAssignment(
            id: uid,
            title: title,
            courseName: course,
            dueDate: dateProperty.flatMap { parseDate($0.value, params: $0.params) },
            htmlURL: properties["URL"].flatMap { URL(string: $0.value) },
            videoIDs: AppBlockingManager.youTubeVideoIDs(in: unescapeText(properties["DESCRIPTION"]?.value ?? "")),
            details: plainText(fromHTML: (properties["DESCRIPTION"]?.value ?? "").replacingOccurrences(of: "\\n", with: "\n", options: .caseInsensitive)
                .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";"))
        )
    }

    #if DEBUG
    /// Debug-only checks of the description converter, run when an account is activated.
    private static func selfCheckDescriptions() {
        assert(plainText(fromHTML: "<p>Read <b>chapter&nbsp;3</b>.</p><p>Bring &amp; share</p>") == "Read chapter 3.\nBring & share")
        assert(plainText(fromHTML: "<script>alert(1)</script>Hello<style>p{}</style>") == "Hello", "script and style are dropped")
        assert(plainText(fromHTML: "&amp;lt;b&amp;gt;") == "&lt;b&gt;", "nothing is decoded twice")
        assert(plainText(fromHTML: "Line1<br>Line2<br/>Line3") == "Line1\nLine2\nLine3")
        assert(plainText(fromHTML: String(repeating: "a", count: 5000)).count == 1201, "a long description is cut")
    }
    #endif

    /// An assignment's description turned into plain text for display: script and style blocks dropped, line breaks kept, the
    /// rest of the tags removed, common entities decoded, blank lines and runs of spaces collapsed, and the result cut to
    /// `limit` characters. It is only ever shown as text, never rendered as HTML.
    nonisolated static func plainText(fromHTML html: String, limit: Int = 1200) -> String {
        var text = String(html.prefix(40_000))
        for pattern in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>|</tr>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // &amp; last, so "&amp;lt;" ends up as the text "&lt;" and not "<".
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
                                    ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        let lines = text.split(whereSeparator: \.isNewline).map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }.filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "\u{2026}" : joined
    }

    nonisolated private static func unescapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    nonisolated private static func parseDate(_ value: String, params: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if params.uppercased().contains("VALUE=DATE") && !params.uppercased().contains("VALUE=DATE-TIME") || value.count == 8 {
            // All-day due date: treat it as due at the end of that local day.
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            guard let day = formatter.date(from: value) else { return nil }
            return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day)
        }
        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value)
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let tzid = params.split(separator: ";")
            .first { $0.uppercased().hasPrefix("TZID=") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        formatter.timeZone = tzid.flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.date(from: value)
    }
}
