import XCTest
@testable import Wanderer

final class SplitMathTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    func testEqualSplit() {
        let amounts = SplitMath.amounts(
            total: 90,
            mode: .equal,
            participants: [a, b, c],
            inputs: [:]
        )
        XCTAssertEqual(amounts[a] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(amounts[b] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(amounts[c] ?? 0, 30, accuracy: 0.001)
    }

    func testExactSplit() {
        let amounts = SplitMath.amounts(
            total: 90,
            mode: .exact,
            participants: [a, b],
            inputs: [a: 50, b: 40]
        )
        XCTAssertEqual(amounts[a] ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(amounts[b] ?? 0, 40, accuracy: 0.001)
    }

    func testPercentSplit() {
        let amounts = SplitMath.amounts(
            total: 90,
            mode: .percent,
            participants: [a, b],
            inputs: [a: 50, b: 50]
        )
        XCTAssertEqual(amounts[a] ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(amounts[b] ?? 0, 45, accuracy: 0.001)
    }

    func testShareSplit() {
        let amounts = SplitMath.amounts(
            total: 90,
            mode: .shares,
            participants: [a, b],
            inputs: [a: 1, b: 2]
        )
        XCTAssertEqual(amounts[a] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(amounts[b] ?? 0, 60, accuracy: 0.001)
    }

    func testBalancesAndSettlement() {
        let expenses = [
            SplitMathExpense(
                payer: a,
                amount: 90,
                splits: [a: 30, b: 30, c: 30]
            )
        ]
        let settlements = [
            SplitMathSettlement(from: b, to: a, amount: 30)
        ]

        let balances = SplitMath.balances(
            members: [a, b, c],
            expenses: expenses,
            settlements: settlements
        )

        XCTAssertEqual(balances[a] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(balances[b] ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(balances[c] ?? 0, -30, accuracy: 0.001)
    }

    func testSettlementClearsBalance() {
        let expenses = [
            SplitMathExpense(payer: a, amount: 60, splits: [a: 30, b: 30])
        ]
        let settlements = [
            SplitMathSettlement(from: b, to: a, amount: 30)
        ]
        let balances = SplitMath.balances(
            members: [a, b],
            expenses: expenses,
            settlements: settlements
        )
        XCTAssertEqual(balances[a] ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(balances[b] ?? 0, 0, accuracy: 0.001)
    }
}
