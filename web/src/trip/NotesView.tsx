import { CalendarDays, Clock3, Download, MapPin, Printer, Save, Wallet } from "lucide-react";
import { useEffect, useState } from "react";
import { useToast } from "../components/Toast";
import { fmtDateRange, fmtDateLong } from "../lib/dates";
import { countdownLabel } from "../lib/dates";
import { googleMapsUrl, calendarFileForBundle, downloadText } from "../lib/exports";
import type { TripStore } from "./useTripStore";

export function NotesView({ store }: { store: TripStore }) {
  const { toast } = useToast();
  const bundle = store.bundle;
  const trip = bundle?.trip;
  const [notes, setNotes] = useState(trip?.notes ?? "");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setNotes(trip?.notes ?? "");
  }, [trip?.notes]);

  async function save() {
    setSaving(true);
    try {
      await store.updateTrip({ notes });
      toast("Trip notes saved", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't save the notes.", "error");
    } finally {
      setSaving(false);
    }
  }

  function downloadCalendar() {
    if (!bundle) return;
    const exportBundle = { ...bundle, places: store.places, reservations: store.reservations };
    downloadText(`${trip?.title || "Wanderer trip"}.ics`, calendarFileForBundle(exportBundle));
    toast("Calendar file downloaded", "success");
  }

  const allRoute = googleMapsUrl(store.places);
  const days = bundle?.days ?? [];

  return (
    <div className="tool-page notes-page">
      <header className="tool-heading">
        <div>
          <p className="context-line">The margin notes</p>
          <h1>Notes & exports</h1>
          <p>The loose thoughts that don't belong to one day, plus the plans you can take with you.</p>
        </div>
        <button type="button" className="button button--primary" onClick={() => void save()} disabled={saving || !store.canWrite}>
          <Save size={16} /> {saving ? "Saving…" : "Save notes"}
        </button>
      </header>

      <div className="notes-layout">
        <section className="notes-editor-card">
          <label className="field">
            <span className="field__label">Notes for the whole trip</span>
            <textarea
              rows={14}
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              placeholder="The address of the friend you're meeting, the phrase you want to learn, the thing you don't want to forget…"
              readOnly={!store.canWrite}
            />
          </label>
          <div className="notes-editor-card__foot">
            <span>{notes.trim().length ? `${notes.trim().length} characters` : "Nothing written yet"}</span>
            <button type="button" className="text-link" onClick={() => void save()} disabled={saving || !store.canWrite || notes === (trip?.notes ?? "")}>
              Save changes
            </button>
          </div>
        </section>

        <aside className="trip-facts-card">
          <p className="context-line">At a glance</p>
          <h2>{trip?.title}</h2>
          <dl className="trip-facts">
            <div><dt><MapPin size={14} /> Destination</dt><dd>{trip?.destination || "Not set"}</dd></div>
            <div><dt><CalendarDays size={14} /> Dates</dt><dd>{fmtDateRange(trip?.start_date ?? null, trip?.end_date ?? null)}</dd></div>
            <div><dt><Clock3 size={14} /> Timezone</dt><dd>{trip?.timezone}</dd></div>
            <div><dt><Wallet size={14} /> Currency</dt><dd>{trip?.currency}</dd></div>
          </dl>
          <p className="trip-facts__countdown">{countdownLabel(trip?.start_date ?? null, trip?.end_date ?? null)}</p>

          <div className="export-links">
            <button type="button" className="export-link" onClick={() => window.print()}>
              <Printer size={16} /> <span><strong>Print itinerary</strong><small>Clean, paper-ready plan</small></span>
            </button>
            <button type="button" className="export-link" onClick={downloadCalendar}>
              <Download size={16} /> <span><strong>Download calendar</strong><small>Timed stops and bookings (.ics)</small></span>
            </button>
            {allRoute && (
              <a className="export-link" href={allRoute} target="_blank" rel="noreferrer">
                <MapPin size={16} /> <span><strong>Open all stops in Google Maps</strong><small>Route across the whole trip</small></span>
              </a>
            )}
          </div>
        </aside>
      </div>

      <section className="notes-day-list">
        <div className="section-heading section-heading--compact">
          <h2>Day notes</h2>
        </div>
        {days.length === 0 ? (
          <p className="quiet-note">No days to annotate yet.</p>
        ) : (
          <div className="notes-day-grid">
            {days.map((day) => (
              <article className="notes-day" key={day.id}>
                <span className="notes-day__date">{fmtDateLong(day.date)}</span>
                <h3>{day.title || `Day ${day.day_index + 1}`}</h3>
                <p>{day.notes || "No note for this day."}</p>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
