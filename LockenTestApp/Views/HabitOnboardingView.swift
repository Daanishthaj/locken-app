import SwiftUI

// MARK: - Feature choices (shared by first-sign-in onboarding and Settings)

private struct HabitFeatureRow: Identifiable {
    let id: WritableKeyPath<HabitFeatures, Bool>
    let symbol: String
    let title: String
    let detail: String

    static let all: [HabitFeatureRow] = [
        HabitFeatureRow(id: \.today, symbol: "checkmark.circle", title: "Today view",
                        detail: "A quick strip of today's habits with a progress ring."),
        HabitFeatureRow(id: \.history, symbol: "flame", title: "Streaks & history",
                        detail: "Browse past weeks and see a 12-week map for each habit."),
        HabitFeatureRow(id: \.autoTracking, symbol: "wand.and.stars", title: "Auto-tracking",
                        detail: "Habits that tick themselves from focus sessions or social-media time."),
        HabitFeatureRow(id: \.reminders, symbol: "bell", title: "Reminders",
                        detail: "A nudge at a time you pick, only on days it's still not done."),
    ]
}

private struct HabitFeatureToggles: View {
    @Binding var features: HabitFeatures
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            ForEach(HabitFeatureRow.all) { row in
                HStack(spacing: 14) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(row.detail)
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $features[dynamicMember: row.id])
                        .toggleStyle(GlassSwitchToggleStyle())
                        .labelsHidden()
                        .accessibilityLabel(row.title)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
            }
        }
    }
}

// MARK: - First visit to the Habit Tracker

/// Shown in place of the tracker the first time an account opens the Habit Tracker page:
/// pick which features to use (changeable later in Settings) and whether to start with examples.
struct HabitSetupCard: View {
    @ObservedObject private var store = HabitStore.shared
    @State private var features = HabitFeatures()
    @State private var start = "Start with examples"

    private let accent = SquircleTokens.accentColor(for: "analytics")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up your Habit Tracker")
                    .font(.appFont(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("Choose what you'd like to use. You can change this anytime in Settings.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            HabitFeatureToggles(features: $features, accent: accent)

            HStack {
                JellyRadioPicker(items: ["Start with examples", "Start empty"], selection: $start, label: "Starting habits")
                Spacer()
                Button {
                    store.completeOnboarding(features: features, seedExamples: start == "Start with examples")
                } label: {
                    Text("Continue")
                        .font(.appFont(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }
}

// MARK: - Settings

struct HabitFeaturesCard: View {
    @ObservedObject private var store = HabitStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Habit Tracker")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Turn features on or off. Your habits and history are kept either way.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            HabitFeatureToggles(
                features: Binding(get: { store.features }, set: { store.setFeatures($0) }),
                accent: SquircleTokens.accentColor(for: "customize")
            )
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
    }
}
