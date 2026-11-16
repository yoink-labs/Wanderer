import SwiftUI

/// "Plan my day" — the day's stops and saved ideas, ordered and scheduled by
/// Apple's on-device model. Nothing leaves the phone, and every proposed stop
/// is a place the traveller already saved.
struct AIDaySheet: View {
    let trip: Trip
    let day: TripDayRecord?
    @ObservedObject var store: TripDetailStore
    @Environment(\.dismiss) private var dismiss

    @State private var preference = ""
    @State private var plan: AIPlan?
    @State private var isPlanning = false
    @State private var errorText: String?
    @State private var applied = false

    private var availability: OnDeviceAI.Availability { OnDeviceAI.availability }

    private var dayStops: [PlaceRecord] {
        guard let day else { return [] }
        return store.places(for: day.id)
    }

    private var ideaStops: [PlaceRecord] {
        store.places.filter { $0.dayId == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch availability {
                    case .unsupported(let reason):
                        unavailableCard(reason)
                    case .ready:
                        readyContent
                    }
                }
                .padding(.horizontal, WandererTheme.screenPadding)
                .padding(.vertical, 14)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Plan my day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't plan that day", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Orders the stops you already have into a realistic day and sets start times. Runs on this iPhone — nothing is sent anywhere.")
                .font(.ligga(.footnote))
                .foregroundStyle(WandererTheme.muted)

            if dayStops.isEmpty && ideaStops.isEmpty {
                Text("Add a few stops first, then I can order them for you.")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anything special about this day?")
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                    TextField("e.g. food and markets, no museums, easy pace", text: $preference, axis: .vertical)
                        .font(.ligga(.subheadline))
                        .lineLimit(1...3)
                        .padding(12)
                        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WandererTheme.line, lineWidth: 1))
                        .accessibilityIdentifier("ai-day-preference")
                }

                Button {
                    Task { await runPlan() }
                } label: {
                    HStack(spacing: 8) {
                        if isPlanning {
                            ProgressView().controlSize(.small).tint(WandererTheme.onPrimary)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isPlanning ? "Planning…" : (plan == nil ? "Plan this day" : "Plan again"))
                            .font(.ligga(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(WandererTheme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(WandererTheme.primaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPlanning)
                .accessibilityIdentifier("ai-plan-day")

                if let plan {
                    planCard(plan)
                }
            }

            Text("On-device AI can be wrong about details like opening hours. It only rearranges places you saved.")
                .font(.ligga(.caption2))
                .foregroundStyle(WandererTheme.muted)
        }
    }

    private func planCard(_ plan: AIPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.theme)
                .wandererHeading(.section)
                .foregroundStyle(WandererTheme.ink)

            ForEach(plan.stops) { stop in
                HStack(alignment: .top, spacing: 10) {
                    Text(stop.startTime)
                        .font(.ligga(.footnote, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.coralDeep)
                        .frame(width: 48, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name)
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                        Text("\(stop.minutes) min · \(stop.why)")
                            .font(.ligga(.caption))
                            .foregroundStyle(WandererTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                Task { await apply(plan) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: applied ? "checkmark" : "arrow.down.to.line")
                    Text(applied ? "Applied to this day" : "Apply to this day")
                        .font(.ligga(.subheadline, weight: .bold))
                }
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(applied)
            .accessibilityIdentifier("ai-apply-plan")
        }
        .padding(12)
        .background(WandererTheme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func unavailableCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
            Text("On-device planning isn't available")
                .wandererHeading(.section)
                .foregroundStyle(WandererTheme.ink)
            Text(reason)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
            Text("Everything else still works: add stops, reorder them and set times by hand.")
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
        }
        .padding(16)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Actions

    private func runPlan() async {
        guard !isPlanning else { return }
        isPlanning = true
        errorText = nil
        applied = false
        defer { isPlanning = false }

        do {
            plan = try await OnDeviceAI.planDay(
                destination: trip.destination,
                dayLabel: day.map { "Day \($0.dayIndex + 1) (\($0.fullDateLabel))" } ?? "this day",
                existing: dayStops.map(\.name),
                ideas: ideaStops.map(\.name),
                preference: preference
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()
    }

    static func matchesLoosely(_ name: String, _ target: String) -> Bool {
        let candidate = normalized(name)
        guard !candidate.isEmpty, !target.isEmpty else { return false }
        return candidate.contains(target) || target.contains(candidate)
    }

    /// Writes the plan back: stops already on the day get their start time,
    /// unscheduled ones move onto the day first.
    private func apply(_ plan: AIPlan) async {
        applied = false
        for stop in plan.stops {
            // The model usually echoes the name exactly, but tolerate small
            // differences (articles, accents, a dropped word) rather than
            // silently skipping a stop.
            let target = Self.normalized(stop.name)
            let match = dayStops.first { Self.normalized($0.name) == target }
                ?? ideaStops.first { Self.normalized($0.name) == target }
                ?? dayStops.first { Self.matchesLoosely($0.name, target) }
                ?? ideaStops.first { Self.matchesLoosely($0.name, target) }
            guard let match else { continue }
            if match.dayId != day?.id, let day {
                await store.assign(match, to: day.id)
            }
            await store.setStartTime(match, to: stop.startTime)
        }
        applied = true
        LiggaHaptics.success()
    }
}
