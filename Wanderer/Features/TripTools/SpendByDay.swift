import Charts
import SwiftUI

/// Spend per trip day, for the budget chart. Expenses dated outside the trip
/// (deposits, flights booked months ahead) are counted as "before" or
/// "after" rather than dropped, so the bars always add up to the total.
struct DailySpend: Identifiable, Equatable {
    let id: String
    let label: String
    let amount: Double
    let isTripDay: Bool

    static func series(expenses: [ExpenseRecord], days: [TripDayRecord]) -> [DailySpend] {
        let ordered = days.sorted { $0.dayIndex < $1.dayIndex }
        let dates = ordered.compactMap(\.date)
        var byDate: [String: Double] = [:]
        var before = 0.0, after = 0.0
        for expense in expenses {
            let day = String(expense.spentAt.prefix(10))
            if let first = dates.first, day < first {
                before += expense.amount
            } else if let last = dates.last, day > last {
                after += expense.amount
            } else {
                byDate[day, default: 0] += expense.amount
            }
        }
        var series: [DailySpend] = []
        if before > 0 {
            series.append(DailySpend(id: "before", label: "Before", amount: before, isTripDay: false))
        }
        for day in ordered {
            let key = day.date ?? "day-\(day.dayIndex)"
            series.append(DailySpend(
                id: key,
                label: "\(day.dayIndex + 1)",
                amount: day.date.flatMap { byDate[$0] } ?? 0,
                isTripDay: true
            ))
        }
        if after > 0 {
            series.append(DailySpend(id: "after", label: "After", amount: after, isTripDay: false))
        }
        return series
    }
}

/// Bars per day in marigold, with the daily budget as a dashed line when one
/// is set. Days over budget switch to the signal colour.
struct SpendByDayChart: View {
    let series: [DailySpend]
    let dailyBudget: Double?
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spend by day")
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                Spacer()
                if let dailyBudget {
                    Text("\(TripToolsFormat.money(dailyBudget, code: currency)) a day")
                        .font(.ligga(.footnote, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.muted)
                }
            }

            Chart {
                ForEach(series) { item in
                    BarMark(
                        x: .value("Day", item.label),
                        y: .value("Spent", item.amount),
                        width: .ratio(0.6)
                    )
                    .cornerRadius(5)
                    .foregroundStyle(color(for: item))
                    .accessibilityLabel(item.isTripDay ? "Day \(item.label)" : item.label)
                    .accessibilityValue(TripToolsFormat.money(item.amount, code: currency))
                }
                if let dailyBudget {
                    RuleMark(y: .value("Daily budget", dailyBudget))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(WandererTheme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(WandererTheme.line)
                    AxisValueLabel().foregroundStyle(WandererTheme.muted)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(WandererTheme.muted)
                }
            }
            .frame(height: 150)
        }
        .padding(16)
        .liggaCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spend by day")
    }

    private func color(for item: DailySpend) -> Color {
        if !item.isTripDay { return WandererTheme.sea.opacity(0.55) }
        if let dailyBudget, item.amount > dailyBudget { return WandererTheme.signal }
        return WandererTheme.route
    }
}
