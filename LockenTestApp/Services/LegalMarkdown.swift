import Foundation

/// The legal documents bundled with the app (single source: `docs/legal/` in the repository).
enum LegalDocument: String, CaseIterable, Identifiable {
    case terms = "TERMS_OF_SERVICE"
    case privacy = "PRIVACY_POLICY"
    case acceptableUse = "ACCEPTABLE_USE_POLICY"
    case security = "SECURITY_AND_DATA_PROTECTION_POLICY"
    case credits = "ACKNOWLEDGEMENTS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "Terms of Service"
        case .privacy: return "Privacy Policy"
        case .acceptableUse: return "Acceptable Use Policy"
        case .security: return "Security & Data Protection Policy"
        case .credits: return "Credits & Licenses"
        }
    }

    /// Short name for the switcher in the reader.
    var shortTitle: String {
        switch self {
        case .terms: return "Terms"
        case .privacy: return "Privacy"
        case .acceptableUse: return "Acceptable Use"
        case .security: return "Security"
        case .credits: return "Credits"
        }
    }

    /// Matches links between the documents ("PRIVACY_POLICY.md") and the app's own `locken-legal:privacy` links.
    init?(url: URL) {
        if url.scheme == "locken-legal" {
            let name = url.absoluteString.replacingOccurrences(of: "locken-legal:", with: "")
            guard let match = Self.allCases.first(where: { "\($0)".lowercased() == name.lowercased() }) else { return nil }
            self = match
            return
        }
        guard url.scheme == nil || url.isFileURL else { return nil }
        let file = (url.path as NSString).lastPathComponent
        guard let match = Self.allCases.first(where: { $0.rawValue + ".md" == file }) else { return nil }
        self = match
    }

    func load(from bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: rawValue, withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Splits the documents' Markdown into blocks the reader can lay out natively. Covers what the documents use:
/// headings, paragraphs, bullets, numbered steps, block quotes, tables and rules. Inline styling and links are
/// left in each block's text for `AttributedString(markdown:)`.
enum LegalMarkdown {
    enum Block: Hashable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(indent: Int, text: String)
        case numbered(marker: String, text: String)
        case quote(String)
        case table(header: [String], rows: [[String]])
        case rule
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        let lines = markdown.components(separatedBy: .newlines)
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if trimmed == "---" {
                flushParagraph()
                blocks.append(.rule)
                index += 1
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level: level, text: trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)))
                index += 1
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(lines[index].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                let text = quoted.joined(separator: " ")
                // Notes to whoever edits the document aren't shown to students.
                if !text.contains("Drafting note") { blocks.append(.quote(text)) }
            } else if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = cellsOf(lines[index])
                    if !cells.allSatisfy(isSeparatorCell) { rows.append(cells) }
                    index += 1
                }
                if let header = rows.first { blocks.append(.table(header: header, rows: Array(rows.dropFirst()))) }
            } else if let bullet = bulletText(line) {
                flushParagraph()
                blocks.append(.bullet(indent: bullet.indent, text: bullet.text))
                index += 1
            } else if let numbered = numberedText(trimmed) {
                flushParagraph()
                blocks.append(.numbered(marker: numbered.marker, text: numbered.text))
                index += 1
            } else {
                paragraph.append(trimmed)
                index += 1
            }
        }
        flushParagraph()
        return blocks
    }

    private static func cellsOf(_ line: String) -> [String] {
        var parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    /// "- text" or "* text", with two spaces of indent per nesting level.
    private static func bulletText(_ line: String) -> (indent: Int, text: String)? {
        let spaces = line.prefix(while: { $0 == " " }).count
        let rest = line.dropFirst(spaces)
        guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else { return nil }
        return (spaces / 2, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    /// "1. text".
    private static func numberedText(_ trimmed: String) -> (marker: String, text: String)? {
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (digits + ".", String(trimmed.dropFirst(digits.count + 2)))
    }

    /// Bold, italics, code and links inside one block.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
