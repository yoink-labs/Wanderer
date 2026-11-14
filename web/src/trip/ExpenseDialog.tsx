import { Check, LoaderCircle } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Dialog } from "../components/Dialog";
import { useToast } from "../components/Toast";
import { categoryLabels, money, summaryName } from "../lib/format";
import { equalShares, roundMoney } from "../lib/money";
import { todayKey } from "../lib/dates";
import type { ExpenseCategory, SplitMode } from "../types";
import type { TripStore } from "./useTripStore";

const CATEGORIES: ExpenseCategory[] = ["food", "lodging", "transport", "activities", "shopping", "other"];

export function ExpenseDialog({ open, onClose, store }: { open: boolean; onClose: () => void; store: TripStore }) {
  const { toast } = useToast();
  const currency = store.bundle?.trip.currency ?? "USD";
  const members = store.bundle?.members ?? [];
  const currentUserId = store.currentUserId ?? members[0]?.user_id ?? null;
  const [title, setTitle] = useState("");
  const [amount, setAmount] = useState("");
  const [category, setCategory] = useState<ExpenseCategory>("food");
  const [paidBy, setPaidBy] = useState(currentUserId ?? "");
  const [splitMode, setSplitMode] = useState<"equal" | "exact">("equal");
  const [participants, setParticipants] = useState<string[]>(members.map((member) => member.user_id));
  const [exactAmounts, setExactAmounts] = useState<Record<string, string>>({});
  const [spentAt, setSpentAt] = useState(todayKey());
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setTitle("");
    setAmount("");
    setCategory("food");
    setPaidBy(currentUserId ?? "");
    setSplitMode("equal");
    setParticipants(members.map((member) => member.user_id));
    setExactAmounts({});
    setSpentAt(todayKey());
    setNotes("");
    setError(null);
  }, [open, currentUserId, members.map((member) => member.user_id).join("|")]); // eslint-disable-line react-hooks/exhaustive-deps

  const total = Number(amount) || 0;
  const shares = useMemo(() => equalShares(total, participants), [total, participants]);

  if (!open) return null;

  function toggleParticipant(userId: string) {
    setParticipants((current) =>
      current.includes(userId) ? current.filter((id) => id !== userId) : [...current, userId],
    );
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!title.trim()) {
      setError("Name this expense.");
      return;
    }
    if (!Number.isFinite(total) || total <= 0) {
      setError("Add an amount greater than zero.");
      return;
    }
    if (!paidBy) {
      setError("Choose who paid.");
      return;
    }
    if (!participants.length) {
      setError("Choose at least one person to split with.");
      return;
    }
    let splits: Array<{ user_id: string; amount: number }>;
    if (splitMode === "exact") {
      splits = participants.map((userId) => ({
        user_id: userId,
        amount: roundMoney(Number(exactAmounts[userId] ?? 0)),
      }));
      const sum = roundMoney(splits.reduce((value, split) => value + split.amount, 0));
      if (Math.abs(sum - total) > 0.011) {
        setError(`The exact shares add up to ${money(sum, currency)}, not ${money(total, currency)}.`);
        return;
      }
    } else {
      splits = equalShares(total, participants);
    }
    setSaving(true);
    try {
      await store.addExpense({
        title: title.trim(),
        amount: roundMoney(total),
        currency,
        category,
        paid_by: paidBy,
        split_with: participants,
        split_mode: splitMode,
        spent_at: spentAt,
        notes: notes.trim() || null,
        splits,
      });
      toast("Expense added", "success");
      onClose();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't add this expense.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Add an expense"
      description={`Recorded in ${currency}. Split it equally or enter exact amounts.`}
      wide
      footer={
        <>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={saving}>Cancel</button>
          <button type="submit" form="expense-form" className="button button--primary" disabled={saving || !store.canWrite}>
            {saving ? <LoaderCircle size={16} className="spin" /> : <Check size={16} />}
            {saving ? "Saving…" : "Add expense"}
          </button>
        </>
      }
    >
      <form id="expense-form" className="dialog-form" onSubmit={submit}>
        <div className="field-row">
          <label className="field field--grow">
            <span className="field__label">What was it?</span>
            <input autoFocus value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Dinner at the night market" />
          </label>
          <label className="field field--amount">
            <span className="field__label">Amount</span>
            <div className="money-input">
              <span>{currency}</span>
              <input inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" />
            </div>
          </label>
        </div>

        <fieldset className="field field--fieldset">
          <legend className="field__label">Category</legend>
          <div className="category-grid">
            {CATEGORIES.map((item) => (
              <button
                key={item}
                type="button"
                className={`category-choice ${category === item ? "is-active" : ""}`}
                onClick={() => setCategory(item)}
                aria-pressed={category === item}
              >
                {categoryLabels[item]}
              </button>
            ))}
          </div>
        </fieldset>

        <div className="field-row">
          <label className="field">
            <span className="field__label">Paid by</span>
            <select value={paidBy} onChange={(event) => setPaidBy(event.target.value)}>
              {members.map((member) => (
                <option value={member.user_id} key={member.user_id}>
                  {member.user_id === currentUserId ? "You" : summaryName(member.display_name, member.email)}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span className="field__label">Date</span>
            <input type="date" value={spentAt} onChange={(event) => setSpentAt(event.target.value)} />
          </label>
        </div>

        <fieldset className="field field--fieldset">
          <legend className="field__label">Split</legend>
          <div className="segmented segmented--compact">
            <button type="button" className={splitMode === "equal" ? "is-active" : ""} onClick={() => setSplitMode("equal")}>
              Equally
            </button>
            <button type="button" className={splitMode === "exact" ? "is-active" : ""} onClick={() => setSplitMode("exact")}>
              Exact amounts
            </button>
          </div>
          <div className="split-list">
            {members.map((member) => {
              const chosen = participants.includes(member.user_id);
              const equalShare = shares.find((share) => share.user_id === member.user_id)?.amount ?? 0;
              return (
                <div className={`split-row ${chosen ? "is-chosen" : ""}`} key={member.user_id}>
                  <label className="split-row__person">
                    <input type="checkbox" checked={chosen} onChange={() => toggleParticipant(member.user_id)} />
                    <span>{member.user_id === currentUserId ? "You" : summaryName(member.display_name, member.email)}</span>
                  </label>
                  {chosen && (
                    splitMode === "equal" ? (
                      <span className="split-row__amount">{money(equalShare, currency)}</span>
                    ) : (
                      <label className="split-row__input">
                        <span className="sr-only">Exact amount for {summaryName(member.display_name, member.email)}</span>
                        <input
                          inputMode="decimal"
                          value={exactAmounts[member.user_id] ?? ""}
                          onChange={(event) => setExactAmounts((current) => ({ ...current, [member.user_id]: event.target.value }))}
                          placeholder="0.00"
                        />
                      </label>
                    )
                  )}
                </div>
              );
            })}
          </div>
        </fieldset>

        <label className="field">
          <span className="field__label">Notes <span className="field__optional">optional</span></span>
          <input value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Cash, shared taxi, who had the extra glass…" />
        </label>

        {error && <p className="form-error" role="alert">{error}</p>}
        {store.offline && <p className="form-error">You're offline. Reconnect to add an expense.</p>}
      </form>
    </Dialog>
  );
}
