import AppKit
import SwiftUI

// MARK: - Installed apps

/// An app found in Applications, with whether Locken would block it on its own.
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL
    let isBuiltInDistraction: Bool
    var id: String { bundleID }
}

/// Reads the apps in /Applications, ~/Applications and /System/Applications (top level and one folder down).
/// Only each app's Info.plist is read, which needs no special permission.
enum InstalledAppsScanner {
    static func scan(onlyBlockable: Bool = true) -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        var found: [String: InstalledApp] = [:]
        func add(_ url: URL) {
            guard url.pathExtension == "app", let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                  found[bundleID] == nil, !onlyBlockable || AppBlockingManager.canBeBlocked(bundleID: bundleID),
                  bundleID != Bundle.main.bundleIdentifier else { return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            let builtIn = DistractionRules.isDistraction(bundleID: bundleID, name: name, bundlePath: url.path, category: category)
            found[bundleID] = InstalledApp(bundleID: bundleID, name: name, url: url, isBuiltInDistraction: builtIn)
        }
        for root in roots {
            let items = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let inner = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    inner.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Blocked apps card

/// Lets the student choose which apps the Shield closes during focus sessions. Locken's own picks (games,
/// social media) start on; anything installed can be added; tapping a tile takes it off again.
struct BlockedAppsCard: View {
    @ObservedObject private var blocker = AppBlockingManager.shared
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = true
    @State private var showingPicker = false

    var accent: Color = SquircleTokens.accentColor(for: "customize")

    private var blockedApps: [InstalledApp] {
        let installed = apps.filter { blocker.isBlocked(bundleID: $0.bundleID, builtIn: $0.isBuiltInDistraction) }
        // Apps the student added that aren't in Applications any more still show, so they can be removed.
        let installedIDs = Set(apps.map(\.bundleID))
        let missing = blocker.userBlockedApps
            .filter { !installedIDs.contains($0.key) }
            .map { InstalledApp(bundleID: $0.key, name: $0.value, url: URL(fileURLWithPath: "/"), isBuiltInDistraction: false) }
        return (installed + missing).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var keptOpen: [InstalledApp] {
        apps.filter { $0.isBuiltInDistraction && blocker.userAllowedApps.contains($0.bundleID) }
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blocked apps")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("These close while a focus session runs with the Shield on. Click an app to keep it open instead.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                LogoTraceLoader(size: 16, strokeWidth: 9)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(blockedApps) { app in
                        BlockedAppTile(app: app, isBlocked: true, accent: accent) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                blocker.setBlocked(false, bundleID: app.bundleID, name: app.name, builtIn: app.isBuiltInDistraction)
                            }
                        }
                    }
                    AddAppTile(accent: accent) { showingPicker = true }
                }

                if blockedApps.isEmpty {
                    Text("Nothing is blocked. Add the apps that distract you.")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }

                if !keptOpen.isEmpty {
                    Text("Kept open: " + keptOpen.map(\.name).joined(separator: ", "))
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Browsers are never closed; Locken closes social media and YouTube tabs in them instead.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerObsidianCard(cornerRadius: 16)
        .task {
            guard apps.isEmpty else { return }
            apps = await Task.detached(priority: .userInitiated) { InstalledAppsScanner.scan() }.value
            isLoading = false
        }
        .sheet(isPresented: $showingPicker) {
            AddBlockedAppSheet(apps: apps, accent: accent)
        }
    }
}

/// One app on the block list: its real icon and name, with an accent ring. Hover only brightens the border.
private struct BlockedAppTile: View {
    let app: InstalledApp
    let isBlocked: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconImage(url: app.url)
                    .frame(width: 34, height: 34)
                Text(app.name)
                    .font(.appFont(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 96, height: 78)
            .background(shape.fill(isBlocked ? accent.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(shape.strokeBorder(isBlocked ? accent : Color.white.opacity(isHovered ? 0.22 : 0.08), lineWidth: isBlocked ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isBlocked ? "Keep \(app.name) open during sessions" : "Block \(app.name) during sessions")
        .accessibilityLabel(app.name)
        .accessibilityValue(isBlocked ? "Blocked" : "Not blocked")
        .accessibilityHint(isBlocked ? "Keeps it open during sessions" : "Closes it during sessions")
    }
}

private struct AddAppTile: View {
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 34, height: 34)
                Text("Add App")
                    .font(.appFont(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(width: 96, height: 78)
            .background(shape.fill(Color.white.opacity(0.03)))
            .overlay(shape.strokeBorder(Color.white.opacity(isHovered ? 0.24 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Add an app to block")
    }
}

/// The app's real icon from Finder; a generic app icon when it isn't installed any more.
struct AppIconImage: View {
    let url: URL
    var body: some View {
        let icon = url.path == "/"
            ? NSWorkspace.shared.icon(for: .application)
            : NSWorkspace.shared.icon(forFile: url.path)
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .accessibilityHidden(true)
    }
}

/// Search the installed apps and tick the ones to block.
private struct AddBlockedAppSheet: View {
    let apps: [InstalledApp]
    let accent: Color
    @ObservedObject private var blocker = AppBlockingManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose apps to block")
                    .font(.appFont(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search apps", text: $search)
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
                )
                .accessibilityLabel("Search apps")

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(results) { app in
                        let blocked = blocker.isBlocked(bundleID: app.bundleID, builtIn: app.isBuiltInDistraction)
                        BlockedAppTile(app: app, isBlocked: blocked, accent: accent) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                blocker.setBlocked(!blocked, bundleID: app.bundleID, name: app.name, builtIn: app.isBuiltInDistraction)
                            }
                        }
                    }
                }
                .padding(2)
            }

            Text("Work apps like Xcode or Canva are never blocked unless you pick them here.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(Spacing.l)
        .frame(width: 620, height: 520)
        .background(SquircleTokens.bgBottom(for: "customize"))
    }
}

// MARK: - Videos for this session

/// YouTube videos schoolwork needs. Paste links (several at once is fine); only these videos stay open while the
/// Shield is on, and the rest of YouTube still closes. Videos linked in a Canvas assignment are added when its
/// session starts. The list clears when the session ends.
struct SessionVideosCard: View {
    @ObservedObject private var blocker = AppBlockingManager.shared
    @State private var links = ""
    @State private var note: String?

    private let accent = SquircleTokens.accentColor(for: "focus")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIDEOS FOR THIS SESSION")
                .font(.appFont(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.55))

            Text("Need YouTube for schoolwork? Paste the video links here. Only these videos stay open; the rest of YouTube still closes.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("youtube.com/watch?v=… or youtu.be/…", text: $links)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    )
                    .onSubmit(add)
                    .accessibilityLabel("YouTube video links")
                Button("Allow", action: add)
                    .buttonStyle(.plain)
                    .quietAction()
                    .disabled(links.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let note {
                Text(note)
                    .font(.appFont(size: 11))
                    .foregroundColor(SquircleTokens.textGold)
            }

            ForEach(blocker.allowedVideoIDs, id: \.self) { id in
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(accent)
                        .accessibilityHidden(true)
                    Link("youtu.be/\(id)", destination: URL(string: "https://youtu.be/\(id)")!)
                        .font(.appFont(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Button {
                        blocker.removeAllowedVideo(id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop allowing video \(id)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .innerObsidianCard(cornerRadius: 10)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }

    private func add() {
        let found = AppBlockingManager.youTubeVideoIDs(in: links)
        _ = blocker.allowVideos(from: links)
        note = found.isEmpty ? "No YouTube video links found. Paste a link like youtube.com/watch?v=… or youtu.be/…" : nil
        if !found.isEmpty { links = "" }
    }
}
