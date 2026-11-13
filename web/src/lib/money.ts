import type { Expense, ExpenseSplit, Member, Settlement } from "../types";
import { summaryName } from "./format";

export interface DirectedDebt {
  from: string;
  to: string;
  amount: number;
}

export interface MemberNet {
  member: Member;
  name: string;
  net: number;
}

export function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function equalShares(amount: number, userIds: string[]): Array<{ user_id: string; amount: number }> {
  if (!userIds.length) return [];
  const totalCents = Math.round(amount * 100);
  const base = Math.floor(totalCents / userIds.length);
  const remainder = totalCents - base * userIds.length;
  return userIds.map((user_id, index) => ({
    user_id,
    amount: (base + (index < remainder ? 1 : 0)) / 100,
  }));
}

export function sharesForExpense(expense: Expense, splits: ExpenseSplit[]): Array<{ user_id: string; amount: number }> {
  const stored = splits.filter((split) => split.expense_id === expense.id);
  if (stored.length && stored.some((split) => split.amount > 0)) {
    return stored.map((split) => ({ user_id: split.user_id, amount: split.amount }));
  }
  if (!expense.split_with?.length) return [];
  if (expense.split_mode === "equal" || expense.split_mode === "exact") {
    return equalShares(expense.amount, expense.split_with);
  }
  if (expense.split_mode === "percent" && stored.length) {
    return stored.map((split) => ({ user_id: split.user_id, amount: roundMoney(expense.amount * (split.amount / 100)) }));
  }
  if (expense.split_mode === "shares" && stored.length) {
    const totalWeight = stored.reduce((sum, split) => sum + (split.weight ?? 0), 0);
    if (totalWeight > 0) {
      return stored.map((split) => ({ user_id: split.user_id, amount: roundMoney((expense.amount * (split.weight ?? 0)) / totalWeight) }));
    }
  }
  return equalShares(expense.amount, expense.split_with);
}

export function memberNets(
  expenses: Expense[],
  splits: ExpenseSplit[],
  settlements: Settlement[],
  members: Member[],
): MemberNet[] {
  const net = new Map<string, number>();
  for (const member of members) net.set(member.user_id, 0);

  for (const expense of expenses) {
    if (expense.paid_by) {
      net.set(expense.paid_by, (net.get(expense.paid_by) ?? 0) + expense.amount);
    }
    for (const share of sharesForExpense(expense, splits)) {
      net.set(share.user_id, (net.get(share.user_id) ?? 0) - share.amount);
    }
  }
  for (const settlement of settlements) {
    net.set(settlement.from_user, (net.get(settlement.from_user) ?? 0) + settlement.amount);
    net.set(settlement.to_user, (net.get(settlement.to_user) ?? 0) - settlement.amount);
  }

  return members.map((member) => ({
    member,
    name: summaryName(member.display_name, member.email),
    net: roundMoney(net.get(member.user_id) ?? 0),
  }));
}

export function simplifyDebts(nets: MemberNet[]): DirectedDebt[] {
  const debtors = nets.filter((net) => net.net < -0.005).map((net) => ({ id: net.member.user_id, amount: -net.net }));
  const creditors = nets.filter((net) => net.net > 0.005).map((net) => ({ id: net.member.user_id, amount: net.net }));
  debtors.sort((a, b) => b.amount - a.amount);
  creditors.sort((a, b) => b.amount - a.amount);
  const debts: DirectedDebt[] = [];
  let debtorIndex = 0;
  let creditorIndex = 0;
  while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
    const debtor = debtors[debtorIndex];
    const creditor = creditors[creditorIndex];
    const amount = roundMoney(Math.min(debtor.amount, creditor.amount));
    if (amount > 0.005) debts.push({ from: debtor.id, to: creditor.id, amount });
    debtor.amount = roundMoney(debtor.amount - amount);
    creditor.amount = roundMoney(creditor.amount - amount);
    if (debtor.amount <= 0.005) debtorIndex += 1;
    if (creditor.amount <= 0.005) creditorIndex += 1;
  }
  return debts;
}

export function splitLabel(mode: string): string {
  switch (mode) {
    case "equal": return "Split equally";
    case "exact": return "Exact amounts";
    case "percent": return "By percentage";
    case "shares": return "By shares";
    default: return "Split";
  }
}

export function categoryTotals(expenses: Expense[]): Array<{ category: string; amount: number }> {
  const totals = new Map<string, number>();
  for (const expense of expenses) {
    totals.set(expense.category, roundMoney((totals.get(expense.category) ?? 0) + expense.amount));
  }
  return [...totals.entries()]
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount);
}

export function totalExpenses(expenses: Expense[]): number {
  return roundMoney(expenses.reduce((sum, expense) => sum + expense.amount, 0));
}
