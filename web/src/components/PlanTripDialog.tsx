import { CalendarDays, MapPin, Plus, Sparkles } from "lucide-react";
import { useEffect, useId, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useSession } from "../auth/session";
import { createGuestTrip } from "../lib/guest";
import { dateOnly, estimatedTimezone, timezoneOptions, todayKey } from "../lib/dates";
import type { NewTripInput } from "../types";
import { useToast } from "./Toast";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "SEK", "NOK", "DKK", "CNY", "KRW", "INR", "MXN", "BRL", "NZD", "SGD", "THB", "ISK"];

export function PlanTripDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const session = useSession();
  const navigate = useNavigate();
  const { toast } = useToast();
  const timezoneListId = useId();
  const [destination, setDestination] = useState("");
  const [title, setTitle] = useState("");
  const [startDate, setStartDate] = useState(todayKey());
  const [endDate, setEndDate] = useState(dateOnly(new Date(Date.now() + 4 * 86_400_000)));
  const [currency, setCurrency] = useState(() => localStorage.getItem("wanderer.currency") || "USD");
  const [timezone, setTimezone] = useState(estimatedTimezone);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const timezones = useMemo(timezoneOptions, []);

  useEffect(() => {
    if (!open) return;
    setError(null);
    if (!destination && !title) {
      setStartDate(todayKey());
      setEndDate(dateOnly(new Date(Date.now() + 4 * 86_400_000)));
    }
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!session.isSignedIn) return;
    let cancelled = false;
    session.api
      .me()
      .then((profile) => {
        if (cancelled) return;
        if (profile.currency) setCurrency(profile.currency);
        if (profile.locale) localStorage.setItem("wanderer.locale", profile.locale);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [session.api, session.isSignedIn]);

  if (!open) return null;

  const cleanDestination = destination.trim();
  const cleanTitle = title.trim() || (cleanDestination ? `Trip to ${cleanDestination.split(",")[0]}` : "");

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!cleanDestination) {
      setError("Add a destination so your trip has a place to go.");
      return;
    }
    if (!cleanTitle) {
      setError("Give your trip a title.");
      return;
    }
    if (!startDate || !endDate) {
      setError("Choose a start and end date.");
      return;
    }
    if (endDate < startDate) {
      setError("The end date can't be before the start date.");
      return;
    }
    setSaving(true);
    const input: NewTripInput = {
      title: cleanTitle,
      destination: cleanDestination,
      start_date: startDate,
      end_date: endDate,
      currency: currency || "USD",
      timezone: timezone || "UTC",
    };
    localStorage.setItem("wanderer.currency", input.currency);
    try {
      if (session.isSignedIn) {
        const trip = await session.api.createTrip(input);
        toast("Trip created", "success");
        onClose();
        navigate(`/trips/${trip.id}`);
      } else {
        const bundle = createGuestTrip(input);
        toast("Trip saved on this device", "success");
        onClose();
        navigate(`/trips/${bundle.trip.id}`);
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't create the trip.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="dialog-backdrop-fallback" role="presentation">
      <div className="plan-dialog" role="dialog" aria-modal="true" aria-labelledby="plan-title">
        <div className="plan-dialog__intro">
          <span className="plan-dialog__icon"><Sparkles size={20} /></span>
          <p className="context-line">A new page in your atlas</p>
          <h2 id="plan-title">Where are you going?</h2>
          <p>Name the place, pick the days, and Wanderer will lay out the canvas. You can change everything later.</p>
          <div className="plan-dialog__guest-note">
            {session.isSignedIn
              ? "Your trip is saved to your account and can be shared with the people coming along."
              : "Planning as a guest saves this trip on this device. Sign in whenever you want to keep it with your account."}
          </div>
        </div>
        <form className="plan-form" onSubmit={submit}>
          <div className="plan-form__top">
            <button type="button" className="icon-button icon-button--quiet plan-form__close" onClick={onClose} aria-label="Close">
              ×
            </button>
          </div>
          <label className="field field--hero">
            <span className="field__label"><MapPin size={14} /> Destination</span>
            <input
              autoFocus
              value={destination}
              onChange={(event) => setDestination(event.target.value)}
              placeholder="Lisbon, Portugal"
              className="field__input field__input--destination"
              required
            />
          </label>
          <label className="field">
            <span className="field__label">Trip title <span className="field__optional">optional</span></span>
            <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder={cleanDestination ? `Trip to ${cleanDestination.split(",")[0]}` : "A name for this trip"} />
          </label>
          <div className="field-row">
            <label className="field">
              <span className="field__label"><CalendarDays size={14} /> Start</span>
              <input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} required />
            </label>
            <label className="field">
              <span className="field__label">End</span>
              <input type="date" min={startDate} value={endDate} onChange={(event) => setEndDate(event.target.value)} required />
            </label>
          </div>
          <div className="field-row">
            <label className="field">
              <span className="field__label">Currency</span>
              <select value={currency} onChange={(event) => setCurrency(event.target.value)}>
                {CURRENCIES.map((code) => <option value={code} key={code}>{code}</option>)}
              </select>
            </label>
            <label className="field">
              <span className="field__label">Timezone</span>
              <input
                list={timezoneListId}
                value={timezone}
                onChange={(event) => setTimezone(event.target.value)}
                spellCheck={false}
                placeholder="Europe/Lisbon"
              />
              <datalist id={timezoneListId}>
                {timezones.map((zone) => <option value={zone} key={zone} />)}
              </datalist>
            </label>
          </div>
          {error && <p className="form-error" role="alert">{error}</p>}
          <div className="plan-form__actions">
            <button type="button" className="button button--secondary" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="button button--primary" disabled={saving}>
              <Plus size={17} /> {saving ? "Creating…" : "Create trip"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
