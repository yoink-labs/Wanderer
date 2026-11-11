import SwiftUI
import UIKit

/// What a booking ticket shows at each end of its route, derived from the
/// reservation without any network lookups.
struct BookingTicketModel: Equatable {
    struct End: Equatable {
        /// Short, large label: an airport/station code when one is present,
        /// otherwise the place name.
        var mark: String
        var caption: String?
        var time: String?
    }

    var origin: End
    var destination: End?
    /// "2 nights", "3h 20m", nil when unknown.
    var span: String?
    var isStay: Bool

    init(reservation: ReservationRecord, timeZone: TimeZone, locale: Locale = .current) {
        isStay = reservation.type == .lodging || reservation.type == .car

        let codes = Self.codes(in: reservation.title)
        let start = reservation.startLocation?.tripToolsNilIfEmpty
        let end = reservation.endLocation?.tripToolsNilIfEmpty
        let startTime = reservation.parsedStart.map { Self.time($0, timeZone: timeZone, locale: locale, withDay: false) }

        if isStay {
            let checkIn = reservation.type == .car ? "Pick up" : "Check in"
            let checkOut = reservation.type == .car ? "Drop off" : "Check out"
            origin = End(
                mark: reservation.parsedStart.map { Self.shortDay($0, timeZone: timeZone, locale: locale) } ?? checkIn,
                caption: reservation.parsedStart == nil ? nil : checkIn,
                time: startTime
            )
            destination = reservation.parsedEnd.map {
                End(mark: Self.shortDay($0, timeZone: timeZone, locale: locale), caption: checkOut,
                    time: Self.time($0, timeZone: timeZone, locale: locale, withDay: false))
            }
            if let nights = Self.nights(from: reservation.parsedStart, to: reservation.parsedEnd, timeZone: timeZone) {
                let unit = reservation.type == .car ? "day" : "night"
                span = nights == 1 ? "1 \(unit)" : "\(nights) \(unit)s"
            } else {
                span = nil
            }
            return
        }

        let sameDay = Self.sameDay(reservation.parsedStart, reservation.parsedEnd, timeZone: timeZone)
        origin = End(mark: codes?.0 ?? start ?? reservation.title, caption: codes == nil ? nil : start, time: startTime)
        if codes != nil || end != nil || reservation.parsedEnd != nil {
            destination = End(
                mark: codes?.1 ?? end ?? "Arrive",
                caption: codes == nil ? nil : end,
                time: reservation.parsedEnd.map { Self.time($0, timeZone: timeZone, locale: locale, withDay: !sameDay) }
            )
        } else {
            destination = nil
        }
        span = Self.duration(from: reservation.parsedStart, to: reservation.parsedEnd)
    }

    /// "NRT → ITM", "NRT-ITM", "nrt to itm" → ("NRT", "ITM").
    static func codes(in title: String) -> (String, String)? {
        let pattern = #"^\s*([A-Za-z]{3})\s*(?:→|->|–|-|to)\s*([A-Za-z]{3})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let a = Range(match.range(at: 1), in: title),
              let b = Range(match.range(at: 2), in: title) else { return nil }
        return (title[a].uppercased(), title[b].uppercased())
    }

    static func nights(from start: Date?, to end: Date?, timeZone: TimeZone) -> Int? {
        guard let start, let end, end > start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, days)
    }

    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end, end > start else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes >= 24 * 60 { return nil }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private static func sameDay(_ a: Date?, _ b: Date?, timeZone: TimeZone) -> Bool {
        guard let a, let b else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(a, inSameDayAs: b)
    }

    private static func time(_ date: Date, timeZone: TimeZone, locale: Locale, withDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(withDay ? "EEEjmm" : "jmm")
        return formatter.string(from: date)
    }

    /// "Nov 8": short enough for the display face on a narrow phone.
    private static func shortDay(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}

/// A ticket with a perforated tear line: the top shows the route (or stay)
/// in large type joined by the marigold route line; the stub carries the
/// provider, cost and a tap-to-copy confirmation code.
struct BookingTicket: View {
    let reservation: ReservationRecord
    let timeZone: TimeZone
    let currency: String

    @State private var copied = false
    @State private var measuredStubHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var model: BookingTicketModel { BookingTicketModel(reservation: reservation, timeZone: timeZone) }
    private static let stubHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)

            route
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            perforation

            stub
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(minHeight: Self.stubHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredStubHeight = $0 }
        }
        .background(
            TicketShape(notchY: nil, notchRadius: 10, cornerRadius: WandererTheme.cardRadius, stubHeight: measuredStubHeight)
                .fill(WandererTheme.card)
                .shadow(color: WandererTheme.cardShadow(colorScheme), radius: 12, x: 0, y: 5)
        )
        .overlay(
            TicketShape(notchY: nil, notchRadius: 10, cornerRadius: WandererTheme.cardRadius, stubHeight: measuredStubHeight)
                .stroke(WandererTheme.line, lineWidth: 1)
                .opacity(0.8)
        )
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: reservation.type.icon)
                .font(.ligga(.footnote, weight: .bold))
                .foregroundStyle(WandererTheme.onAccent)
                .frame(width: glyphSize, height: glyphSize)
                .background(WandererTheme.route, in: Circle())
                .accessibilityHidden(true)
            Text(headerTitle)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let span = model.span {
                Text(span)
                    .font(.ligga(.footnote, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WandererTheme.accentText)
            }
        }
    }

    /// The type for coded routes ("Flight"), the name otherwise, never the
    /// same words twice on one ticket.
    private var headerTitle: String {
        if BookingTicketModel.codes(in: reservation.title) != nil { return reservation.type.title }
        if !model.isStay, model.origin.mark == reservation.title { return reservation.type.title }
        return reservation.title
    }

    @ViewBuilder
    private var route: some View {
        if let destination = model.destination {
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                endView(model.origin, alignment: .leading)
                if !stacked {
                    connector
                        .padding(.top, 14)
                }
                endView(destination, alignment: stacked ? .leading : .trailing)
            }
        } else {
            endView(model.origin, alignment: .leading)
        }
    }

    private func endView(_ end: BookingTicketModel.End, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(end.mark)
                .font(end.mark.count <= 4 ? .display(.largeTitle) : .display(.title2))
                .foregroundStyle(WandererTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            if let caption = end.caption {
                Text(caption)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
            }
            if let time = end.time {
                Text(time)
                    .font(.ligga(.headline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WandererTheme.ink)
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: alignment == .leading ? .leading : .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The signature route line between the two ends, with the type's glyph
    /// riding on it.
    private var connector: some View {
        ZStack {
            HStack(spacing: 0) {
                Circle().fill(WandererTheme.route).frame(width: 7, height: 7)
                Rectangle()
                    .fill(WandererTheme.route)
                    .frame(height: 3)
                Circle().stroke(WandererTheme.route, lineWidth: 2.5).frame(width: 8, height: 8)
            }
            Image(systemName: reservation.type == .flight ? "airplane" : reservation.type.icon)
                .font(.ligga(.footnote, weight: .bold))
                .foregroundStyle(WandererTheme.accentText)
                .padding(.horizontal, 6)
                .background(WandererTheme.card)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var perforation: some View {
        Line()
            .stroke(WandererTheme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .frame(height: 1)
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
    }

    private var stub: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 1) {
                if let provider = reservation.provider?.tripToolsNilIfEmpty {
                    Text(provider)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(1)
                }
                if let cost = reservation.cost {
                    Text(TripToolsFormat.money(cost, code: reservation.currency ?? currency))
                        .font(.ligga(.footnote, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.muted)
                }
            }
            if !stacked {
                Spacer(minLength: 6)
            }
            if let code = reservation.confirmationCode?.tripToolsNilIfEmpty {
                Button {
                    UIPasteboard.general.string = code
                    LiggaHaptics.success()
                    withAnimation(WandererMotion.animation(WandererMotion.snappy, reduceMotion: reduceMotion)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(WandererMotion.animation(WandererMotion.gentle, reduceMotion: reduceMotion)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? "Copied" : code)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            .contentTransition(.opacity)
                    }
                    .font(.ligga(.footnote, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(WandererTheme.routeSoft, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.liggaPressable)
                .accessibilityLabel("Confirmation \(code)")
                .accessibilityHint("Copies the confirmation code")
            }
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Rounded ticket with a semicircular notch on each side at the tear line,
/// `stubHeight` above the bottom edge.
struct TicketShape: Shape {
    var notchY: CGFloat?
    var notchRadius: CGFloat
    var cornerRadius: CGFloat
    var stubHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let y = notchY ?? (rect.maxY - stubHeight)
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let notches = Path { notch in
            notch.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
            notch.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        }
        path = path.subtracting(notches)
        return path
    }
}
