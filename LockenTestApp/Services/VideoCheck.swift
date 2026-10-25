import AppKit
import SwiftUI

// MARK: - Deciding whether a video is schoolwork

/// Decides whether a YouTube video belongs in a study session.
///
/// It looks the video up with YouTube's public oEmbed endpoint (title and channel only, no account or key), then
/// asks the student's AI provider when one is set up (18+, their own key, only title / channel / goal are sent).
/// Without AI, or if the AI fails, it uses local rules: known education channels and study words count for it,
/// entertainment words count against it, and Shorts are never allowed.
enum VideoEducationCheck {
    struct Verdict: Equatable {
        let isEducational: Bool
        let title: String?
        let reason: String
    }

    static func check(link: String, goal: String) async -> Verdict {
        guard let id = AppBlockingManager.youTubeVideoIDs(in: link).first else {
            return Verdict(isEducational: false, title: nil, reason: "That isn't a YouTube video link.")
        }
        if link.lowercased().contains("/shorts/") {
            return Verdict(isEducational: false, title: nil, reason: "Shorts aren't allowed during a focus session.")
        }
        let info = await lookUp(id: id)
        let title = info?.title ?? ""
        let channel = info?.channel ?? ""

        if await AITaskFormatter.shared.canJudgeVideos, !title.isEmpty,
           let judged = try? await AITaskFormatter.shared.judgeVideo(title: title, channel: channel, goal: goal) {
            let reason = judged.reason.isEmpty
                ? (judged.isEducational ? "Looks like schoolwork." : "Doesn't look like schoolwork.")
                : judged.reason
            return Verdict(isEducational: judged.isEducational, title: info?.title, reason: reason)
        }
        return rules(title: title, channel: channel)
    }

    // MARK: Local rules

    private static let educationChannels = [
        "khan academy", "crashcourse", "crash course", "ted-ed", "3blue1brown", "mit opencourseware", "organic chemistry tutor",
        "professor leonard", "bozeman science", "amoeba sisters", "numberphile", "computerphile", "veritasium", "kurzgesagt",
        "minutephysics", "smarter every day", "pbs", "national geographic", "harvard", "stanford", "yale", "coursera", "edx",
        "freecodecamp", "cs50", "mathologer", "eddie woo", "patrickjmt", "heimler", "simple history", "extra history",
        "math antics", "nancy pi", "the science asylum", "sixty symbols", "periodic videos", "tom scott",
    ]
    private static let studyWords = [
        "lecture", "lesson", "tutorial", "explained", "explanation", "how to", "course", "chapter", "unit ", "review",
        "practice", "study", "exam", "test prep", "ap ", "sat ", "act ", "calculus", "algebra", "geometry", "trigonometry",
        "statistics", "chemistry", "physics", "biology", "history", "economics", "grammar", "essay", "homework", "guide",
        "introduction", "intro to", "fundamentals", "theorem", "equation", "problem set", "worksheet", "notes", "summary",
        "analysis", "documentary", "science", "math", "programming", "coding", "language", "vocabulary", "spanish", "french",
    ]
    private static let funWords = [
        "prank", "reaction", "funny", "fails", "meme", "gameplay", "minecraft", "fortnite", "roblox", "vlog", "mukbang",
        "challenge", "tiktok", "compilation", "music video", "official video", "lyrics", "trailer", "asmr", "unboxing",
        "highlights", "#shorts", "stream", "let's play", "speedrun",
    ]

    static func rules(title: String, channel: String) -> Verdict {
        let t = " " + title.lowercased() + " "
        let c = channel.lowercased()
        let shownTitle = title.isEmpty ? nil : title
        if title.isEmpty {
            return Verdict(isEducational: false, title: nil,
                           reason: "Couldn't look this video up. If it's for class, add it in Focus › Videos for this session.")
        }
        if let word = funWords.first(where: { t.contains($0) }) {
            return Verdict(isEducational: false, title: shownTitle, reason: "Looks like entertainment (\"\(word.trimmingCharacters(in: .whitespaces))\").")
        }
        if c == "ted" || educationChannels.contains(where: { c.contains($0) }) {
            return Verdict(isEducational: true, title: shownTitle, reason: "\(channel) is an education channel.")
        }
        if studyWords.contains(where: { t.contains($0) }) {
            return Verdict(isEducational: true, title: shownTitle, reason: "The title looks like a lesson or study video.")
        }
        return Verdict(isEducational: false, title: shownTitle,
                       reason: "Couldn't tell it's for school. If it is, add it in Focus › Videos for this session.")
    }

    // MARK: oEmbed

    private struct OEmbed: Decodable {
        let title: String
        let author_name: String?
    }

    private static func lookUp(id: String) async -> (title: String, channel: String)? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, response) = try? await SecureNetwork.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
        return (String(info.title.prefix(200)), String((info.author_name ?? "").prefix(100)))
    }
}

// MARK: - The overlay

/// A full-screen panel shown when the Shield closes a YouTube video during a session: it asks for the video's
/// link (pre-filled with the one that was closed), checks it, and reopens it when it's schoolwork.
@MainActor
final class VideoCheckManager: ObservableObject {
    static let shared = VideoCheckManager()

    enum Phase: Equatable {
        case asking
        case checking
        case allowed(VideoEducationCheck.Verdict)
        case refused(VideoEducationCheck.Verdict)
    }

    @Published var link = ""
    @Published private(set) var phase: Phase = .asking
    private var panel: CheckInPanel?

    private init() {}

    var isShowing: Bool { panel?.isVisible == true }

    func present(url: String) {
        guard !isShowing else { return }
        link = url
        phase = .asking
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = self.panel ?? CheckInPanel(contentRect: frame)
        panel.setFrame(frame, display: false)
        panel.contentView = NSHostingView(rootView: VideoCheckOverlay(manager: self))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    func check() {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty, phase != .checking else { return }
        phase = .checking
        Task {
            let verdict = await VideoEducationCheck.check(link: link, goal: TestAppStateManager.shared.focusGoal)
            if verdict.isEducational {
                _ = AppBlockingManager.shared.allowVideos(from: link)
                phase = .allowed(verdict)
                if let id = AppBlockingManager.youTubeVideoIDs(in: link).first,
                   let url = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                    try? await Task.sleep(for: .seconds(1.2))
                    NSWorkspace.shared.open(url)
                }
                dismiss()
            } else {
                phase = .refused(verdict)
            }
        }
    }
}

private struct VideoCheckOverlay: View {
    @ObservedObject var manager: VideoCheckManager
    @FocusState private var fieldFocused: Bool
    private let accent = SquircleTokens.accentColor(for: "focus")

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YouTube is blocked during focus")
                        .font(.appFont(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Need a video for class? Paste its link and Locken checks whether it's schoolwork. If it is, it opens; the rest of YouTube stays blocked.")
                        .font(.appFont(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("youtube.com/watch?v=…", text: $manager.link)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    )
                    .focused($fieldFocused)
                    .onSubmit { manager.check() }
                    .disabled(manager.phase == .checking)
                    .accessibilityLabel("YouTube video link")

                result

                HStack {
                    Button("Back to work") { manager.dismiss() }
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(action: { manager.check() }) {
                        HStack(spacing: 8) {
                            if manager.phase == .checking { LogoTraceLoader(size: 16, strokeWidth: 9) }
                            Text(manager.phase == .checking ? "Checking…" : "Check video")
                                .font(.appFont(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .borderGlowButton(accent: accent, isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.phase == .checking || manager.link.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(30)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            )
        }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder private var result: some View {
        switch manager.phase {
        case .allowed(let verdict):
            verdictView(icon: "checkmark.circle.fill", color: SquircleTokens.mintAccent,
                        headline: "Allowed. Opening it now.", verdict: verdict)
        case .refused(let verdict):
            verdictView(icon: "xmark.circle.fill", color: Color(red: 0.96, green: 0.52, blue: 0.52),
                        headline: "Not this one.", verdict: verdict)
        default:
            EmptyView()
        }
    }

    private func verdictView(icon: String, color: Color, headline: String, verdict: VideoEducationCheck.Verdict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                if let title = verdict.title {
                    Text("“\(title)”")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Text(verdict.reason)
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
