import { ArrowRight, CheckCircle2, CreditCard, Plus, ReceiptText, Trash2, Users } from "lucide-react";
import { useMemo, useState } from "react";
import { ConfirmDialog } from "../components/Dialog";
import { useToast } from "../components/Toast";
import { fmtDate } from "../lib/dates";
import { categoryLabels, money, plural, summaryName } from "../lib/format";
import { categoryTotals, memberNets, roundMoney, sharesForExpense, simplifyDebts, splitLabel, totalExpenses } from "../lib/money";
import type { Expense } from "../types";
import { ExpenseDialog } from "./ExpenseDialog";
import type { TripStore } from "./useTripStore";

const CATEGORY_TONE: Record<string, string> = {
  food: "food",
  lodging: "lodging",
  transport: "transport",
  activities: "activities",
  shopping: "shopping",
  other: "other",
};

export function BudgetView({ store }: { store: TripStore }) {
  const { toast } = useToast();
  const [addOpen, setAddOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<Expense | null>(null);
  const [pendingSettlement, setPendingSettlement] = useState<{ from: string; to: string; amount: number; currency: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const bundle = store.bundle;
  const members = bundle?.members ?? [];
  const expenses = bundle?.expenses ?? [];
  const currency = bundle?.trip.currency ?? "USD";
  const { currentUserId } = store;

  const nets = useMemo(
    () => memberNets(expenses, bundle?.expense_splits ?? [], bundle?.settlements ?? [], members),
    [expenses, bundle?.expense_splits, bundle?.settlements, members],
  );
  const debts = useMemo(() => simplifyDebts(nets), [nets]);
  const total = totalExpenses(expenses);
  const categories = categoryTotals(expenses);
  const maxCategory = Math.max(1, ...categories.map((category) => category.amount));
  const outstanding = roundMoney(nets.reduce((sum, net) => sum + Math.max(0, net.net), 0));
  const memberById = new Map(members.map((member) => [member.user_id, member]));
  function memberName(id: string): string {
    const member = memberById.get(id);
    return id === currentUserId ? "You" : member ? summaryName(member.display_name, member.email) : "Traveler";
  }

  async function removeExpense() {
    if (!pendingDelete) return;
    setBusy(true);
    try {
      await store.deleteExpense(pendingDelete.id);
      toast("Expense removed", "success");
      setPendingDelete(null);
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't remove this expense.", "error");
    } finally {
      setBusy(false);
    }
  }

  async function recordPayment() {
    if (!pendingSettlement) return;
    setBusy(true);
    try {
      await store.addSettlement({
        from_user: pendingSettlement.from,
        to_user: pendingSettlement.to,
        amount: pendingSettlement.amount,
        currency: pendingSettlement.currency,
        note: "Settled in Wanderer",
      });
      toast("Payment recorded", "success");
      setPendingSettlement(null);
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't record the payment.", "error");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="tool-page budget-page">
      <header className="tool-heading">
        <div>
          <p className="context-line">Shared costs</p>
          <h1>Budget</h1>
          <p>Keep the group honest without the spreadsheet. Add what you spend, split it, and see who owes what.</p>
        </div>
        <button type="button" className="button button--primary" onClick={() => setAddOpen(true)} disabled={!store.canWrite}>
          <Plus size={17} /> Add expense
        </button>
      </header>

      <section className="budget-hero">
        <div className="budget-hero__total">
          <span className="context-line">Trip total</span>
          <strong>{money(total, currency)}</strong>
          <span>{plural(expenses.length, "expense")} · {plural(members.length, "traveler")}</span>
        </div>
        <div className="budget-hero__balance">
          <span className="context-line">Still to settle</span>
          <strong>{money(outstanding, currency)}</strong>
          <span>{debts.length ? `${plural(debts.length, "payment")} will settle it` : "All square"}</span>
        </div>
        <div className="budget-hero__bars" aria-label="Spending by category">
          {categories.length === 0 ? (
            <p className="quiet-note">No spending recorded yet.</p>
          ) : (
            categories.slice(0, 6).map((category) => (
              <div className="category-bar" key={category.category}>
                <span className={`category-bar__dot category-bar__dot--${CATEGORY_TONE[category.category] ?? "other"}`} />
                <span className="category-bar__label">{categoryLabels[category.category] ?? category.category}</span>
                <span className="category-bar__track">
                  <span className={`category-bar__fill category-bar__fill--${CATEGORY_TONE[category.category] ?? "other"}`} style={{ width: `${Math.max(2, (category.amount / maxCategory) * 100)}%` }} />
                </span>
                <span className="category-bar__amount">{money(category.amount, currency)}</span>
              </div>
            ))
          )}
        </div>
      </section>

      <div className="budget-grid">
        <section className="ledger-panel" aria-labelledby="expense-ledger-heading">
          <div className="section-heading section-heading--compact">
            <div>
              <h2 id="expense-ledger-heading">The ledger</h2>
            </div>
            <span className="count-note">{expenses.length}</span>
          </div>
          {expenses.length === 0 ? (
            <div className="tool-empty tool-empty--inline">
              <span><ReceiptText size={22} /></span>
              <h3>Nothing spent yet</h3>
              <p>Log the first meal, museum ticket, or taxi and the balances will look after themselves.</p>
            </div>
          ) : (
            <div className="expense-list">
              {[...expenses].sort((a, b) => b.spent_at.localeCompare(a.spent_at)).map((expense) => {
                const shares = sharesForExpense(expense, bundle?.expense_splits ?? []);
                return (
                  <div className="expense-row" key={expense.id}>
                    <span className={`expense-row__icon expense-row__icon--${CATEGORY_TONE[expense.category] ?? "other"}`}>
                      <CreditCard size={16} />
                    </span>
                    <span className="expense-row__copy">
                      <strong>{expense.title}</strong>
                      <small>
                        {fmtDate(expense.spent_at, { month: "short", day: "numeric" })} · {expense.paid_by ? `${memberName(expense.paid_by)} paid` : "No payer"} · {splitLabel(expense.split_mode)}
                      </small>
                    </span>
                    <span className="expense-row__people" aria-label={`Split ${expense.split_with.length} ways`}>
                      <Users size={12} /> {expense.split_with.length}
                    </span>
                    <span className="expense-row__amount">{money(expense.amount, expense.currency || currency)}</span>
                    <button
                      type="button"
                      className="icon-button icon-button--quiet is-danger"
                      onClick={() => setPendingDelete(expense)}
                      disabled={!store.canWrite}
                      aria-label={`Remove ${expense.title}`}
                      title="Remove expense"
                    >
                      <Trash2 size={15} />
                    </button>
                    <span className="sr-only">Shares: {shares.map((share) => `${memberName(share.user_id)} ${money(share.amount, expense.currency || currency)}`).join(", ")}</span>
                  </div>
                );
              })}
            </div>
          )}
        </section>

        <aside className="balances-panel" aria-labelledby="balances-heading">
          <div className="section-heading section-heading--compact">
            <div>
              <h2 id="balances-heading">Who owes what</h2>
            </div>
          </div>
          <div className="balance-list">
            {nets.map((net) => (
              <div className="balance-row" key={net.member.user_id}>
                <span className={`balance-row__avatar ${net.net < -0.005 ? "owes" : net.net > 0.005 ? "owed" : ""}`}>
                  {summaryName(net.member.display_name, net.member.email).slice(0, 1).toUpperCase()}
                </span>
                <span className="balance-row__name">{net.member.user_id === currentUserId ? "You" : net.name}</span>
                <span className={`balance-row__amount ${net.net < -0.005 ? "owes" : net.net > 0.005 ? "owed" : ""}`}>
                  {net.net > 0.005 ? `+${money(net.net, currency)}` : net.net < -0.005 ? money(net.net, currency) : "Settled"}
                </span>
              </div>
            ))}
          </div>

          <div className="settle-block">
            <div className="settle-block__heading">
              <h3>Simplest way to settle</h3>
              <CheckCircle2 size={17} />
            </div>
            {debts.length === 0 ? (
              <p className="settle-empty">Everyone is square. The next round is on the group.</p>
            ) : (
              <div className="settle-list">
                {debts.map((debt) => (
                  <div className="settle-row" key={`${debt.from}-${debt.to}`}>
                    <span className="settle-row__text">
                      <strong>{memberName(debt.from)}</strong> pays <strong>{memberName(debt.to)}</strong>
                    </span>
                    <span className="settle-row__amount">{money(debt.amount, currency)}</span>
                    <button
                      type="button"
                      className="text-link"
                      onClick={() => setPendingSettlement({ from: debt.from, to: debt.to, amount: debt.amount, currency })}
                      disabled={!store.canWrite}
                    >
                      Record
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </aside>
      </div>

      <ExpenseDialog open={addOpen} onClose={() => setAddOpen(false)} store={store} />

      <ConfirmDialog
        open={Boolean(pendingDelete)}
        onClose={() => setPendingDelete(null)}
        onConfirm={removeExpense}
        title="Remove this expense?"
        message={pendingDelete ? `${pendingDelete.title} will be removed from the ledger and everyone's balance will update.` : ""}
        confirmLabel="Remove expense"
        destructive
        busy={busy}
      />
      <ConfirmDialog
        open={Boolean(pendingSettlement)}
        onClose={() => setPendingSettlement(null)}
        onConfirm={recordPayment}
        title="Record this payment?"
        message={pendingSettlement ? `${memberName(pendingSettlement.from)} paid ${memberName(pendingSettlement.to)} ${money(pendingSettlement.amount, pendingSettlement.currency)}. This will update the balances.` : ""}
        confirmLabel="Record payment"
        busy={busy}
      />
    </div>
  );
}
