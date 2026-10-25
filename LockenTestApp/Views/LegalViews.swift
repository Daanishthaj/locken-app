import SwiftUI

// MARK: - Reader

/// Shows the Terms, Privacy Policy, Acceptable Use Policy and Security Policy inside the app, laid out natively
/// from the bundled Markdown. Links between the documents switch documents; web links open in the browser.
struct LegalReaderView: View {
    @State var document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    private let linkTint = Color(red: 0.84, green: 0.79, blue: 1.0)

    private var text: String { document.load() ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.s) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)
                }
                JellyRadioPicker(
                    items: LegalDocument.allCases.map(\.shortTitle),
                    selection: Binding(
                        get: { document.shortTitle },
                        set: { title in document = LegalDocument.allCases.first { $0.shortTitle == title } ?? document }
                    ),
                    label: "Legal document"
                )
                .frame(maxWidth: 560)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.m)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(document.title)
                            .font(.appFont(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .id("top")
                        // The drafts still hold details like the company name in [brackets].
                        if text.contains("[Company Name]") {
                            Text("Draft under legal review. Details in [brackets] will be filled in before release.")
                                .font(.appFont(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        if text.isEmpty {
                            Text("This document couldn't be opened.")
                                .font(.appFont(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        ForEach(Array(LegalMarkdown.parse(text).enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block)
                        }
                    }
                    .textSelection(.enabled)
                    .tint(linkTint)
                    .frame(maxWidth: PageWidth.reading, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, PageWidth.margin)
                    .padding(.bottom, PageWidth.margin * 2)
                }
                .onChange(of: document) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let linked = LegalDocument(url: url) {
                document = linked
                return .handled
            }
            return .systemAction
        })
        .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 780)
        .background(SquircleTokens.obsidianBase)
    }
}

/// One Markdown block, laid out natively. Used by the legal reader and the AI digests.
struct MarkdownBlockView: View {
    let block: LegalMarkdown.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            // The document title is already shown above.
            if level == 1 {
                EmptyView()
            } else {
                Text(LegalMarkdown.inline(text))
                    .font(.appFont(size: level == 2 ? 17 : 14, weight: level == 2 ? .bold : .semibold))
                    .foregroundColor(.white.opacity(level == 2 ? 1 : 0.92))
                    .padding(.top, level == 2 ? Spacing.m : Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
            }
        case .paragraph(let text):
            prose(text)
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundColor(.white.opacity(0.6))
                prose(text)
            }
            .font(.appFont(size: 13))
            .padding(.leading, CGFloat(indent) * 18 + 4)
        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                prose(text)
            }
            .padding(.leading, 4)
        case .quote(let text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.25)).frame(width: 3)
                prose(text)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let rows):
            LegalTableView(header: header, rows: rows)
        case .rule:
            SectionDivider().padding(.vertical, Spacing.xs)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(LegalMarkdown.inline(text))
            .font(.appFont(size: 13))
            .foregroundColor(.white.opacity(0.78))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LegalTableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    Text(LegalMarkdown.inline(cell))
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                SectionDivider(subtle: true)
                GridRow {
                    ForEach(0..<header.count, id: \.self) { column in
                        Text(LegalMarkdown.inline(column < row.count ? row[column] : ""))
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .innerObsidianCard(cornerRadius: 12)
    }
}

// MARK: - Settings

/// Settings → Privacy & Legal: what leaves the Mac in plain words, then each document in the reader.
struct LegalCard: View {
    @State private var openDocument: LegalDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Privacy & Legal")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("What Locken shares, and the rules for using it.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 6) {
                privacyLine("Locken's server holds only your email, name, photo and sign-in settings (in the US).")
                privacyLine("Canvas: your token goes only to your school's Canvas.")
                privacyLine("AI: your goal and assignment titles, and your reminders or this week's events when you ask for a digest, go to the AI service you add a key for, only when you use it.")
                privacyLine("New passwords: only 5 characters of a scrambled copy are checked against known leaks.")
                privacyLine("No ads, analytics or tracking. Nothing is sold.")
            }
            .padding(.vertical, 4)
            VStack(spacing: 0) {
                ForEach(LegalDocument.allCases) { document in
                    Button { openDocument = document } label: {
                        HStack {
                            Text(document.title)
                                .font(.appFont(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if document != LegalDocument.allCases.last {
                        SectionDivider(subtle: true)
                    }
                }
            }

            Text(LegalMarkdown.inline("Created by [daanu.focus@gmail.com](mailto:daanu.focus@gmail.com). Questions, privacy or security reports go there too."))
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .tint(Color(red: 0.84, green: 0.79, blue: 1.0))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
        .sheet(item: $openDocument) { LegalReaderView(document: $0) }
    }
}

private func privacyLine(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("•").foregroundColor(.white.opacity(0.5))
        Text(text)
            .font(.appFont(size: 12))
            .foregroundColor(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Sign-up pieces

/// Birth month and year, with nothing chosen at first and no hint of any age limit (a neutral age screen).
struct BirthMonthYearPicker: View {
    @Binding var month: Int?
    @Binding var year: Int?

    private let monthNames = Calendar.current.monthSymbols
    private let years: [Int] = {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 100)...current).reversed()
    }()

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Picker("Month", selection: $month) {
                Text("Month").tag(Int?.none)
                ForEach(1...12, id: \.self) { number in
                    Text(monthNames[number - 1]).tag(Int?.some(number))
                }
            }
            .accessibilityLabel("Birth month")
            Picker("Year", selection: $year) {
                Text("Year").tag(Int?.none)
                ForEach(years, id: \.self) { value in
                    Text(String(value)).tag(Int?.some(value))
                }
            }
            .accessibilityLabel("Birth year")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.appFont(size: 13))
    }
}

/// A checkbox whose label holds links to the legal documents. The links open the in-app reader.
struct AgreementCheckbox: View {
    @Binding var isOn: Bool
    /// Markdown, e.g. "I agree to the [Terms of Service](locken-legal:terms)".
    let label: String
    /// Plain words for VoiceOver.
    let accessibilityText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(accessibilityText, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(accessibilityText)
            Text(LegalMarkdown.inline(label))
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .tint(Color(red: 0.84, green: 0.79, blue: 1.0))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Consent gate (after sign-in)

/// Shown when a signed-in account has no age or agreement on record on this Mac, such as a brand-new Google
/// account created from the Sign In tab. Nothing in Locken opens until it's done. Under 13: the account is
/// deleted (server and this Mac) and sign-up is blocked on this Mac, as on the sign-up form.
struct ConsentGateView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var month: Int?
    @State private var year: Int?
    @State private var agrees = false
    @State private var guardianAgrees = false
    @State private var openDocument: LegalDocument?
    @State private var refusedMessage: String?

    private let accent = Color(red: 0.84, green: 0.79, blue: 1.0)

    private var age: Int? {
        guard let month, let year else { return nil }
        return AgeGate.age(birthMonth: month, birthYear: year)
    }
    /// Shown only once the age is known to be 13–17, so the cutoff isn't hinted at.
    private var needsGuardian: Bool {
        guard let age else { return false }
        return age >= AgeGate.minimumAge && age < AgeGate.adultAge
    }
    private var ready: Bool { age != nil && agrees && (!needsGuardian || guardianAgrees) && !auth.isWorking }

    var body: some View {
        ZStack {
            SquircleTokens.bgBottom(for: "dashboard").ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One more step")
                        .font(.appFont(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Before you start, tell us your date of birth and agree to Locken's terms.")
                        .font(.appFont(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let refusedMessage {
                    Text(refusedMessage)
                        .font(.appFont(size: 13, weight: .medium))
                        .foregroundColor(SquircleTokens.textGold)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // An age already given on this Mac can't be changed, so only the agreement is asked then.
                    if AgeGate.shared.birth == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DATE OF BIRTH")
                                .font(.appFont(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(.white.opacity(0.55))
                            BirthMonthYearPicker(month: $month, year: $year)
                        }
                    }

                    AgreementCheckbox(
                        isOn: $agrees,
                        label: "I agree to the [Terms of Service](locken-legal:terms) and [Privacy Policy](locken-legal:privacy)",
                        accessibilityText: "I agree to the Terms of Service and Privacy Policy"
                    )
                    if needsGuardian {
                        AgreementCheckbox(
                            isOn: $guardianAgrees,
                            label: "My parent or guardian has read the [Terms of Service](locken-legal:terms) and agrees to them",
                            accessibilityText: "My parent or guardian has read the Terms of Service and agrees to them"
                        )
                    }

                    if let message = auth.errorMessage {
                        Text(message)
                            .font(.appFont(size: 12))
                            .foregroundColor(SquircleTokens.textGold)
                    }

                    HStack {
                        Button("Sign Out") { Task { await auth.signOut() } }
                            .buttonStyle(.plain)
                            .quietAction()
                        Spacer()
                        Button(action: confirm) {
                            Text("Continue")
                                .font(.appFont(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 10)
                                .borderGlowButton(accent: accent, isProminent: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.5)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(28)
            .frame(width: 440)
            .luxuryObsidianCard()
        }
        .environment(\.openURL, OpenURLAction { url in
            if let document = LegalDocument(url: url) {
                openDocument = document
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $openDocument) { LegalReaderView(document: $0) }
        .onAppear {
            if let birth = AgeGate.shared.birth {
                month = birth.month
                year = birth.year
            }
        }
    }

    private func confirm() {
        guard ready, let month, let year, let age else { return }
        guard age >= AgeGate.minimumAge else {
            // Under 13: no account. Delete it everywhere and stop sign-up on this Mac.
            AgeGate.blockSignUp()
            refusedMessage = "Sorry, you can't use Locken yet. This account has been deleted."
            Task {
                if await !auth.deleteAccount() { await auth.signOut() }
            }
            return
        }
        if AgeGate.shared.birth == nil { AgeGate.shared.save(month: month, year: year) }
        AgeGate.shared.recordAgreement()
        // Store it on the account too, so other Macs don't ask again (or adopt the account's answer if it has one).
        Task { await AgeGate.shared.syncWithAccount() }
    }
}
