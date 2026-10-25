//
//  GoogleClassroom.swift
//  LockenTestApp
//
//  Reads a student's Google Classroom assignments (course names, assignment titles, due dates, whether each is handed in)
//  with Google's sign-in for apps: the system browser sheet, PKCE, and no client secret. The two scopes are read-only.
//  `CanvasAPIManager` calls this as a third way to link ("Google Classroom") and shows the result in the same lists as
//  Canvas. It needs a Google Cloud OAuth client of type iOS (bundle ID com.locken.LockenTestApp); its ID goes in
//  Info.plist as `GoogleClassroomClientID`. See docs/GOOGLE_CLASSROOM_SETUP.md.
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

enum GoogleClassroom {
    /// The OAuth client ID ("123-abc.apps.googleusercontent.com"). It's public, like Supabase's anon key; empty until set up.
    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClassroomClientID") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    private static let idSuffix = ".apps.googleusercontent.com"
    /// Google's custom-scheme redirect for an iOS-type client is the client ID with its parts reversed.
    static var redirectScheme: String { "com.googleusercontent.apps." + clientID.replacingOccurrences(of: idSuffix, with: "") }
    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    static let scopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
    ]

    enum Failure: Error {
        case notSetUp
        case cancelled
        case signInFailed
        /// The school (Google Workspace) doesn't let students use apps like this.
        case blockedBySchool
        /// The saved sign-in no longer works (revoked, or the password changed): link again.
        case signInAgain
        case noRefreshToken
        case status(Int)
        case unreadable
    }

    struct Tokens: Sendable {
        let accessToken: String
        let refreshToken: String?
    }

    // MARK: Sign-in

    @MainActor private static var session: ASWebAuthenticationSession?
    @MainActor private static let anchor = Anchor()

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }

    nonisolated static func randomURLSafe(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func authorizationURL(clientID: String, redirectURI: String, state: String, challenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Offline access and a fresh consent screen, so Google returns a refresh token every time.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    /// Opens Google's sign-in in a system sheet and trades the result for tokens. The code that comes back is useless
    /// without this call's one-time verifier, and the `state` must match, so a stray redirect can't be used.
    @MainActor
    static func signIn() async throws -> Tokens {
        guard isConfigured else { throw Failure.notSetUp }
        let verifier = randomURLSafe(bytes: 32)
        let state = randomURLSafe(bytes: 16)
        let url = authorizationURL(clientID: clientID, redirectURI: redirectURI, state: state, challenge: challenge(for: verifier))
        defer { Self.session = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? Failure.cancelled : Failure.signInFailed)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            Self.session = session
            // start() is false when the sheet can't open (no window); then Google never calls back.
            if !session.start() { continuation.resume(throwing: Failure.signInFailed) }
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? Failure.cancelled : (error.contains("admin_policy") ? Failure.blockedBySchool : Failure.signInFailed)
        }
        guard value("state") == state, let code = value("code") else { throw Failure.signInFailed }
        return try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "client_id": clientID, "redirect_uri": redirectURI,
        ])
    }

    /// A fresh access token from the saved refresh token.
    static func accessToken(refreshToken: String) async throws -> String {
        try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]).accessToken
    }

    /// Tells Google to forget the grant (when the student unlinks). Best effort: nothing more can be done if it fails.
    static func revoke(refreshToken: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["token": refreshToken])
        _ = try? await SecureNetwork.session.data(for: request)
    }

    nonisolated private static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    }

    nonisolated private static func tokenRequest(_ fields: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)
        let (data, response) = try await SecureNetwork.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            switch json?["error"] as? String {
            case "invalid_grant": throw Failure.signInAgain
            case "access_denied", "admin_policy_enforced": throw Failure.blockedBySchool
            default: throw Failure.status(status)
            }
        }
        guard let access = json?["access_token"] as? String else { throw Failure.unreadable }
        return Tokens(accessToken: access, refreshToken: json?["refresh_token"] as? String)
    }

    // MARK: Classroom data

    struct Course: Equatable { let id: String; let name: String }
    struct Work: Equatable { let id: String; let title: String; let due: Date?; let link: URL? }

    /// Active courses the student is in, then each course's assignments that aren't handed in, as the same
    /// `CanvasAssignment` Canvas produces. A course that refuses (some are restricted) is skipped; the course list itself is required.
    nonisolated static func fetchAssignments(accessToken: String, now: Date = Date()) async throws -> [CanvasAssignment] {
        var courses: [Course] = []
        var page: String?
        for _ in 0..<5 {
            let json = try await get("/v1/courses", [("courseStates", "ACTIVE"), ("studentId", "me"), ("pageSize", "100")], page, accessToken)
            let parsed = parseCourses(json)
            courses += parsed.courses
            page = parsed.next
            if page == nil { break }
        }
        var found: [CanvasAssignment] = []
        var firstFailure: Error?
        var readable = 0
        // shortcut: reads at most 30 active courses (students rarely have more); raise it if one does.
        let wanted = courses.prefix(30)
        await withTaskGroup(of: Result<[CanvasAssignment], Error>.self) { group in
            for course in wanted {
                group.addTask {
                    do { return .success(try await assignments(in: course, accessToken: accessToken)) } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let list):
                    readable += 1
                    found += list
                case .failure(let error):
                    firstFailure = firstFailure ?? error
                }
            }
        }
        // One restricted course is skipped. If none could be read, that's an error, not an empty list.
        if let firstFailure, readable == 0 { throw firstFailure }
        return found
    }

    nonisolated private static func assignments(in course: Course, accessToken: String) async throws -> [CanvasAssignment] {
        var work: [Work] = []
        var page: String?
        for _ in 0..<5 {
            let json = try await get("/v1/courses/\(course.id)/courseWork", [("orderBy", "dueDate asc"), ("pageSize", "100")], page, accessToken)
            let parsed = parseCourseWork(json)
            work += parsed.work
            page = parsed.next
            if page == nil { break }
        }
        var handedIn = Set<String>()
        page = nil
        for _ in 0..<5 {
            let json = try await get("/v1/courses/\(course.id)/courseWork/-/studentSubmissions", [("userId", "me"), ("pageSize", "100")], page, accessToken)
            let parsed = parseSubmissions(json)
            handedIn.formUnion(parsed.handedIn)
            page = parsed.next
            if page == nil { break }
        }
        return work.filter { !handedIn.contains($0.id) }.map {
            CanvasAssignment(id: "gc:\(course.id):\($0.id)", title: $0.title, courseName: course.name, dueDate: $0.due, htmlURL: $0.link)
        }
    }

    nonisolated private static func get(_ path: String, _ query: [(String, String)], _ pageToken: String?, _ accessToken: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://classroom.googleapis.com")!
        components.path = path
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await SecureNetwork.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.status(status) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
        return json
    }

    // MARK: Parsing (pure, so it can be checked)

    nonisolated static func parseCourses(_ json: [String: Any]) -> (courses: [Course], next: String?) {
        let items = json["courses"] as? [[String: Any]] ?? []
        let courses = items.compactMap { item -> Course? in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return Course(id: id, name: String(name.prefix(100)))
        }
        return (courses, json["nextPageToken"] as? String)
    }

    nonisolated static func parseCourseWork(_ json: [String: Any]) -> (work: [Work], next: String?) {
        let items = json["courseWork"] as? [[String: Any]] ?? []
        let work = items.compactMap { item -> Work? in
            guard let id = item["id"] as? String, let title = item["title"] as? String, !title.isEmpty else { return nil }
            let link = (item["alternateLink"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return Work(id: id, title: String(title.prefix(200)), due: dueDate(item["dueDate"] as? [String: Any], item["dueTime"] as? [String: Any]), link: link)
        }
        return (work, json["nextPageToken"] as? String)
    }

    /// Submissions that are handed in (turned in, or returned with a grade): those assignments are done.
    nonisolated static func parseSubmissions(_ json: [String: Any]) -> (handedIn: Set<String>, next: String?) {
        let items = json["studentSubmissions"] as? [[String: Any]] ?? []
        let done = items.compactMap { item -> String? in
            guard let id = item["courseWorkId"] as? String, ["TURNED_IN", "RETURNED"].contains(item["state"] as? String ?? "") else { return nil }
            return id
        }
        return (Set(done), json["nextPageToken"] as? String)
    }

    /// Classroom gives a date and an optional time in UTC. With no time, the work is due at the end of that day here.
    nonisolated static func dueDate(_ date: [String: Any]?, _ time: [String: Any]?, calendar: Calendar = .current) -> Date? {
        guard let year = date?["year"] as? Int, let month = date?["month"] as? Int, let day = date?["day"] as? Int else { return nil }
        if let time {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.date(from: DateComponents(year: year, month: month, day: day, hour: time["hours"] as? Int ?? 0, minute: time["minutes"] as? Int ?? 0))
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 23, minute: 59))
    }

    #if DEBUG
    /// Debug-only checks of the sign-in link and the parsing, run once when Classroom is first used.
    static func selfCheck() {
        // PKCE: the RFC 7636 example verifier gives its documented challenge.
        assert(challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let url = authorizationURL(clientID: "1-a.apps.googleusercontent.com", redirectURI: "com.googleusercontent.apps.1-a:/oauth2redirect", state: "s", challenge: "c")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        assert(query.first { $0.name == "code_challenge_method" }?.value == "S256" && query.first { $0.name == "scope" }?.value?.contains("classroom.coursework.me.readonly") == true)
        assert(!url.absoluteString.contains("client_secret"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let due = dueDate(["year": 2026, "month": 10, "day": 22], ["hours": 3, "minutes": 30])
        assert(due == utc.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 3, minute: 30)), "a due time is UTC")
        assert(dueDate(["year": 2026, "month": 10, "day": 22], nil, calendar: utc) == utc.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23, minute: 59)), "no time: end of day")
        assert(dueDate(nil, nil) == nil)
        let work = parseCourseWork(["courseWork": [
            ["id": "w1", "title": "Essay", "alternateLink": "https://classroom.google.com/c/1/a/2", "dueDate": ["year": 2026, "month": 10, "day": 22]],
            ["id": "w2", "title": "Reading", "alternateLink": "http://insecure.example"],
            ["id": "w3"],
        ], "nextPageToken": "n"])
        assert(work.work.map(\.id) == ["w1", "w2"] && work.next == "n" && work.work[0].link != nil && work.work[1].link == nil && work.work[1].due == nil)
        let done = parseSubmissions(["studentSubmissions": [
            ["courseWorkId": "w1", "state": "TURNED_IN"], ["courseWorkId": "w2", "state": "CREATED"], ["courseWorkId": "w3", "state": "RETURNED"], ["state": "TURNED_IN"],
        ]])
        assert(done.handedIn == ["w1", "w3"] && done.next == nil)
        assert(parseCourses(["courses": [["id": "1", "name": "English 2A"], ["id": "2"]]]).courses == [Course(id: "1", name: "English 2A")])
    }
    #endif
}
