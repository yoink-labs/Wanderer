import { Check, ListChecks, Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import { useToast } from "../components/Toast";
import type { TripStore } from "./useTripStore";

export function ChecklistView({ store }: { store: TripStore }) {
  const { toast } = useToast();
  const items = [...(store.bundle?.checklist ?? [])].sort((a, b) => a.position - b.position);
  const checked = items.filter((item) => item.is_checked).length;
  const progress = items.length ? Math.round((checked / items.length) * 100) : 0;
  const [title, setTitle] = useState("");
  const [adding, setAdding] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function add(event: React.FormEvent) {
    event.preventDefault();
    const clean = title.trim();
    if (!clean) return;
    setAdding(true);
    try {
      await store.addChecklistItem(clean);
      setTitle("");
      toast("Added to the checklist", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't add that item.", "error");
    } finally {
      setAdding(false);
    }
  }

  async function toggle(id: string, value: boolean) {
    const item = items.find((entry) => entry.id === id);
    if (!item) return;
    setBusyId(id);
    try {
      await store.setChecklistChecked(item, value);
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't update the checklist.", "error");
    } finally {
      setBusyId(null);
    }
  }

  async function remove(id: string) {
    setBusyId(id);
    try {
      await store.deleteChecklistItem(id);
      toast("Item removed", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't remove that item.", "error");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="tool-page checklist-page">
      <header className="tool-heading">
        <div>
          <p className="context-line">Before you go</p>
          <h1>Checklist</h1>
          <p>The small things that make the big trip work. One list, shared with everyone on the trip.</p>
        </div>
      </header>

      <div className="checklist-layout">
        <section className="checklist-card">
          <div className="checklist-progress">
            <div>
              <span className="context-line">Packed & ready</span>
              <strong>{checked} <span>of {items.length}</span></strong>
            </div>
            <span className="checklist-progress__percent">{progress}%</span>
            <span className="checklist-progress__track">
              <span style={{ width: `${progress}%` }} />
            </span>
          </div>

          <form className="checklist-add" onSubmit={add}>
            <span className="checklist-add__icon"><Plus size={17} /></span>
            <input
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Add something to remember"
              disabled={!store.canWrite || adding}
              aria-label="New checklist item"
            />
            <button type="submit" className="button button--ink button--small" disabled={!title.trim() || !store.canWrite || adding}>
              {adding ? "Adding…" : "Add"}
            </button>
          </form>

          {items.length === 0 ? (
            <div className="tool-empty tool-empty--inline checklist-empty">
              <span><ListChecks size={22} /></span>
              <h3>The list is open</h3>
              <p>Passports, adapters, the restaurant you keep forgetting to book. Add the first thing.</p>
            </div>
          ) : (
            <ul className="checklist-list">
              {items.map((item) => (
                <li className={`checklist-row ${item.is_checked ? "is-checked" : ""}`} key={item.id}>
                  <button
                    type="button"
                    className={`checklist-check ${item.is_checked ? "is-checked" : ""}`}
                    onClick={() => void toggle(item.id, !item.is_checked)}
                    disabled={!store.canWrite || busyId === item.id}
                    aria-pressed={item.is_checked}
                    aria-label={`${item.is_checked ? "Uncheck" : "Check"} ${item.title}`}
                  >
                    {item.is_checked && <Check size={14} />}
                  </button>
                  <span className="checklist-row__title">{item.title}</span>
                  <button
                    type="button"
                    className="icon-button icon-button--quiet is-danger checklist-row__delete"
                    onClick={() => void remove(item.id)}
                    disabled={!store.canWrite || busyId === item.id}
                    aria-label={`Delete ${item.title}`}
                    title="Delete item"
                  >
                    <Trash2 size={15} />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <aside className="checklist-note">
          <span className="checklist-note__art" aria-hidden="true"><ListChecks size={34} /></span>
          <h2>Small list, calm arrival.</h2>
          <p>Checklist items are shared with everyone on the trip. Ticking something off is visible to the group, so no one packs the same adapter twice.</p>
          <p className="quiet-note">Private packing lists aren't part of this version.</p>
        </aside>
      </div>
    </div>
  );
}
