import Foundation
import SwiftUI
import UIKit

/// Renders a trip as a printable PDF: the itinerary by day, bookings and a
/// spend summary. Native text rendering, no third-party service and no cost.
enum TripPDFExporter {
    static func makePDF(
        trip: Trip,
        days: [TripDayRecord],
        places: [PlaceRecord],
        reservations: [ReservationRecord],
        expenses: [ExpenseRecord]
    ) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72dpi
        let margin: CGFloat = 48
        let contentWidth = page.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        return renderer.pdfData { context in
            var cursorY: CGFloat = margin

            func beginPage() {
                context.beginPage()
                cursorY = margin
            }

            func ensureSpace(_ height: CGFloat) {
                if cursorY + height > page.height - margin {
                    beginPage()
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .label, spacingAfter: CGFloat = 2) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                ensureSpace(bounding.height + spacingAfter)
                (text as NSString).draw(
                    with: CGRect(x: margin, y: cursorY, width: contentWidth, height: bounding.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                cursorY += bounding.height + spacingAfter
            }

            func rule() {
                ensureSpace(12)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: cursorY + 4))
                path.addLine(to: CGPoint(x: page.width - margin, y: cursorY + 4))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                cursorY += 12
            }

            beginPage()

            draw(trip.title, font: .systemFont(ofSize: 26, weight: .bold), spacingAfter: 4)
            var meta = [trip.destination, trip.dateRange]
            if trip.days > 0 { meta.append("\(trip.days) days") }
            draw(meta.filter { !$0.isEmpty }.joined(separator: " · "), font: .systemFont(ofSize: 12), color: .secondaryLabel, spacingAfter: 14)

            if !places.isEmpty {
                draw("ITINERARY", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabel, spacingAfter: 8)
            }

            for day in days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
                let dayPlaces = places
                    .filter { $0.dayId == day.id }
                    .sorted { $0.position < $1.position }
                guard !dayPlaces.isEmpty || day.notes?.isEmpty == false else { continue }

                ensureSpace(60)
                draw(
                    "Day \(day.dayIndex + 1) · \(day.fullDateLabel)",
                    font: .systemFont(ofSize: 14, weight: .semibold),
                    spacingAfter: 4
                )
                if let notes = day.notes, !notes.isEmpty {
                    draw(notes, font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 6)
                }
                for (index, place) in dayPlaces.enumerated() {
                    var line = "\(index + 1). \(place.name)"
                    if let time = place.timeLabel(in: trip.timezone) {
                        line = "\(index + 1). \(time)  \(place.name)"
                    }
                    draw(line, font: .systemFont(ofSize: 11), spacingAfter: 1)
                    let detail = [place.category.title, place.address]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        draw("      \(detail)", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 4)
                    }
                }
                cursorY += 6
            }

            let loose = places.filter { $0.dayId == nil }.sorted { $0.position < $1.position }
            if !loose.isEmpty {
                rule()
                draw("UNSCHEDULED", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabel, spacingAfter: 6)
                for place in loose {
                    draw("• \(place.name)", font: .systemFont(ofSize: 11), spacingAfter: 2)
                }
                cursorY += 6
            }

            if !reservations.isEmpty {
                rule()
                draw("BOOKINGS", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabel, spacingAfter: 6)
                for reservation in reservations {
                    var line = "\(reservation.type.title): \(reservation.title)"
                    if let date = reservation.dateLabel(in: trip.timezone) {
                        line += " — \(date)"
                    }
                    draw(line, font: .systemFont(ofSize: 11), spacingAfter: 2)
                    let detail = [reservation.provider, reservation.confirmationCode]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        draw("      \(detail)", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 4)
                    }
                }
            }

            if !expenses.isEmpty {
                rule()
                draw("SPEND", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabel, spacingAfter: 6)
                let totals = Dictionary(grouping: expenses, by: \.currency)
                    .mapValues { rows in rows.reduce(0) { $0 + $1.amount } }
                    .sorted { $0.key < $1.key }
                for (currency, total) in totals {
                    draw("\(currency) \(String(format: "%.2f", total))", font: .systemFont(ofSize: 12, weight: .semibold), spacingAfter: 2)
                }
            }

            cursorY = max(cursorY, page.height - margin - 24)
            draw(
                "Made with Wanderer · \(Date().formatted(date: .abbreviated, time: .omitted))",
                font: .systemFont(ofSize: 8),
                color: .tertiaryLabel,
                spacingAfter: 0
            )
        }
    }

    /// Writes the PDF to a temporary file, named for the trip, and returns it.
    static func writeTemporaryFile(
        trip: Trip,
        days: [TripDayRecord],
        places: [PlaceRecord],
        reservations: [ReservationRecord],
        expenses: [ExpenseRecord]
    ) -> URL? {
        let data = makePDF(
            trip: trip,
            days: days,
            places: places,
            reservations: reservations,
            expenses: expenses
        )
        let safeTitle = trip.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle.isEmpty ? "Trip" : safeTitle).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Small UIKit bridge so the export can use the system share sheet with a file.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
