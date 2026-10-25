import CryptoKit
import Foundation

/// Password rules following NIST SP 800-63B (Digital Identity Guidelines, rev. 4), the standard most
/// security regulations and audits point to:
/// - At least 8 characters (allowed because every Locken sign-in also needs an emailed code, i.e. the
///   password is never the only factor), and at least 64 characters accepted. All characters, spaces and
///   emoji are allowed.
/// - No composition rules (no forced upper/lower/number/symbol mix) and no forced periodic changes.
/// - Blocklist: breached passwords (Have I Been Pwned, k-anonymity — only 5 characters of the SHA-1 hash
///   leave the Mac), common passwords, context words (the app's name, the email's name) and repetitive or
///   sequential strings.
/// - A strength meter as guidance only: it helps people pick longer passwords but never blocks one on its own.
enum PasswordPolicy {
    struct Assessment: Equatable {
        /// 0 (very weak) … 4 (strong); guidance only.
        var score: Int
        /// Reasons the password can't be used (NIST "SHALL" rules). Empty means it's allowed.
        var problems: [String]
        /// A friendly tip when it's allowed but could be stronger.
        var tip: String?
        var isAcceptable: Bool { problems.isEmpty }

        var label: String { ["Very weak", "Weak", "Fair", "Good", "Strong"][max(0, min(4, score))] }
    }

    static let minimumLength = 8
    static let maximumLength = 64

    private static let commonPasswords: Set<String> = [
        "password", "password1", "password12", "password123", "passw0rd", "p@ssw0rd", "12345678", "123456789",
        "1234567890", "qwertyuiop", "qwerty123", "iloveyou", "letmein1", "welcome1", "admin123", "football",
        "baseball", "sunshine", "princess", "trustno1", "superman", "starwars", "whatever", "freedom1",
        "dragon12", "monkey12", "abc12345", "abcd1234", "11111111", "00000000", "asdfghjkl", "zaq12wsx",
    ]

    /// Instant, offline assessment (the breach check is `isBreached`).
    static func assess(_ password: String, email: String) -> Assessment {
        var problems: [String] = []
        let lower = password.lowercased()
        let length = password.count

        if length < minimumLength { problems.append("Use at least \(minimumLength) characters.") }
        if length > maximumLength { problems.append("Use at most \(maximumLength) characters.") }

        // Context-specific words: the service name and the email's name are the first things attackers try.
        let emailName = email.lowercased().split(separator: "@").first.map(String.init) ?? ""
        if lower.contains("locken") { problems.append("Don't use the app's name.") }
        if emailName.count >= 3, lower.contains(emailName) { problems.append("Don't include your email name.") }

        // Common passwords, including with trailing digits or symbols ("password!", "letmein2024").
        let stripped = String(lower.reversed().drop { !$0.isLetter }.reversed())
        if commonPasswords.contains(lower) || (stripped.count >= 6 && commonPasswords.contains(stripped)) {
            problems.append("That's a very common password.")
        }

        // Repetitive or sequential ("aaaaaaaa", "12345678", "abcdefgh").
        if length >= minimumLength, Set(lower).count < 4 || isSequential(lower) {
            problems.append("Avoid repeated or sequential characters.")
        }

        // Guidance: longer beats complex. Rough entropy from length and the characters actually used.
        let pool = (password.contains { $0.isLowercase } ? 26 : 0) + (password.contains { $0.isUppercase } ? 26 : 0)
            + (password.contains { $0.isNumber } ? 10 : 0) + (password.contains { !$0.isLetter && !$0.isNumber } ? 33 : 0)
        let bits = Double(length) * log2(Double(max(pool, 1)))
        var score = bits >= 75 ? 4 : bits >= 60 ? 3 : bits >= 45 ? 2 : bits >= 30 ? 1 : 0
        if !problems.isEmpty { score = min(score, 1) }

        let tip: String? = problems.isEmpty && score < 3
            ? "Tip: longer is stronger. A few unrelated words, like \u{201C}violet lamp river\u{201D}, works well."
            : nil
        return Assessment(score: score, problems: problems, tip: tip)
    }

    /// True if the password appears in Have I Been Pwned's breach corpus. Nil if the check couldn't run.
    static func isBreached(_ password: String) async -> Bool? {
        let hash = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
        let prefix = hash.prefix(5), suffix = hash.dropFirst(5)
        var request = URLRequest(url: URL(string: "https://api.pwnedpasswords.com/range/\(prefix)")!)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        request.timeoutInterval = 10
        guard let (data, response) = try? await SecureNetwork.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let body = String(decoding: data, as: UTF8.self)
        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":")
            if parts.count == 2, parts[0] == suffix, (Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0) > 0 {
                return true
            }
        }
        return false
    }

    /// The whole password steps up or down by one ("12345678", "hgfedcba").
    private static func isSequential(_ text: String) -> Bool {
        let values = text.unicodeScalars.map { Int($0.value) }
        guard values.count >= 2 else { return false }
        let steps = zip(values, values.dropFirst()).map { $1 - $0 }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }
}
