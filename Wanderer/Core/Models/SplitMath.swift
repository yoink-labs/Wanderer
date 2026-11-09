import Foundation

struct SplitMathExpense {
    let payer: UUID?
    let amount: Double
    let splits: [UUID: Double]
}

struct SplitMathSettlement {
    let from: UUID
    let to: UUID
    let amount: Double
}

enum SplitMath {
    /// Turns a total and per-person inputs into the amount each participant owes.
    static func amounts(
        total: Double,
        mode: ExpenseSplitMode,
        participants: [UUID],
        inputs: [UUID: Double]
    ) -> [UUID: Double] {
        guard !participants.isEmpty, total > 0 else { return [:] }

        switch mode {
        case .equal:
            let share = total / Double(participants.count)
            return Dictionary(uniqueKeysWithValues: participants.map { ($0, share) })

        case .exact:
            return participants.reduce(into: [:]) { result, id in
                result[id] = max(0, inputs[id] ?? 0)
            }

        case .percent:
            return participants.reduce(into: [:]) { result, id in
                result[id] = total * max(0, inputs[id] ?? 0) / 100
            }

        case .shares:
            let weights = participants.map { max(0, inputs[$0] ?? 0) }
            let weightTotal = weights.reduce(0, +)
            guard weightTotal > 0 else { return [:] }
            return Dictionary(uniqueKeysWithValues: zip(participants, weights).map { id, weight in
                (id, total * weight / weightTotal)
            })
        }
    }

    /// Net balance per member. Positive means the member is owed money.
    static func balances(
        members: [UUID],
        expenses: [SplitMathExpense],
        settlements: [SplitMathSettlement]
    ) -> [UUID: Double] {
        var net: [UUID: Double] = [:]

        for expense in expenses {
            for (userId, amount) in expense.splits {
                net[userId, default: 0] -= amount
            }
            if let payer = expense.payer {
                net[payer, default: 0] += expense.amount
            }
        }

        for settlement in settlements {
            net[settlement.from, default: 0] += settlement.amount
            net[settlement.to, default: 0] -= settlement.amount
        }

        return Dictionary(uniqueKeysWithValues: members.map { ($0, net[$0] ?? 0) })
    }
}
