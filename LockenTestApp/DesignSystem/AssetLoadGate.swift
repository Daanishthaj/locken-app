import SwiftUI

/// Holds a page back until everything it loads asynchronously (React components in web views, 3D models)
/// is ready, then fades the whole page in at once, so pieces don't pop in one by one.
/// A page never waits longer than `maxWait`: anything still loading after that fades in on its own.
@MainActor
final class AssetLoadGate: ObservableObject {
    @Published private(set) var isRevealed = false

    static let maxWait: Duration = .milliseconds(1200)
    /// Views that register during the same layout pass get a moment to do so before an empty gate opens.
    private static let settle: Duration = .milliseconds(80)

    private var pending = Set<UUID>()
    private var started = false
    private var settleTask: Task<Void, Never>?

    /// Called by a loading view; hand the id back to `markReady` once it has rendered.
    func register() -> UUID {
        let id = UUID()
        if !isRevealed { pending.insert(id) }
        return id
    }

    func markReady(_ id: UUID) {
        pending.remove(id)
        revealIfSettled()
    }

    func begin() {
        guard !started else { return }
        started = true
        Task {
            try? await Task.sleep(for: Self.maxWait)
            reveal()
        }
        revealIfSettled()
    }

    private func revealIfSettled() {
        guard started, pending.isEmpty, !isRevealed else { return }
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: Self.settle)
            if !Task.isCancelled, pending.isEmpty { reveal() }
        }
    }

    private func reveal() {
        guard !isRevealed else { return }
        withAnimation(.easeOut(duration: 0.35)) { isRevealed = true }
    }
}

private struct AssetLoadGateKey: EnvironmentKey {
    static let defaultValue: AssetLoadGate? = nil
}

extension EnvironmentValues {
    /// The gate of the nearest `revealWhenLoaded()` container, if any.
    var assetLoadGate: AssetLoadGate? {
        get { self[AssetLoadGateKey.self] }
        set { self[AssetLoadGateKey.self] = newValue }
    }
}

private struct RevealWhenLoaded: ViewModifier {
    @StateObject private var gate = AssetLoadGate()

    func body(content: Content) -> some View {
        content
            .environment(\.assetLoadGate, gate)
            .opacity(gate.isRevealed ? 1 : 0)
            .onAppear { gate.begin() }
    }
}

extension View {
    /// Keeps this view invisible until its web components and 3D models have loaded, then fades it in.
    func revealWhenLoaded() -> some View {
        modifier(RevealWhenLoaded())
    }
}
