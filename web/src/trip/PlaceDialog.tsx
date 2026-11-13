import { ArrowLeft, Check, LoaderCircle, MapPin, Search, UserRound } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { Dialog } from "../components/Dialog";
import { PlaceCategoryIcon } from "../components/TripBits";
import { useToast } from "../components/Toast";
import { isoFromZoned, wallTimeInZone } from "../lib/dates";
import type { Place, PlaceCategory, PlaceInput } from "../types";
import type { TripStore } from "./useTripStore";

interface PlaceDialogProps {
  open: boolean;
  onClose: () => void;
  store: TripStore;
  place?: Place | null;
  defaultDayId?: string | null;
  saveAsPersonal?: boolean;
}

interface Fields {
  name: string;
  address: string;
  lat: string;
  lng: string;
  category: PlaceCategory;
  dayId: string;
  startTime: string;
  endTime: string;
  notes: string;
  website: string;
  phone: string;
}

function initialFields(place: Place | null | undefined, dayId: string | null | undefined, timeZone: string): Fields {
  return {
    name: place?.name ?? "",
    address: place?.address ?? "",
    lat: place?.lat != null ? String(place.lat) : "",
    lng: place?.lng != null ? String(place.lng) : "",
    category: place?.category ?? "sight",
    dayId: place?.day_id ?? dayId ?? "",
    startTime: wallTimeInZone(place?.start_time, timeZone),
    endTime: wallTimeInZone(place?.end_time, timeZone),
    notes: place?.notes ?? "",
    website: place?.website ?? "",
    phone: place?.phone ?? "",
  };
}

const CATEGORIES: Array<{ value: PlaceCategory; label: string }> = [
  { value: "sight", label: "Sight" },
  { value: "food", label: "Food" },
  { value: "lodging", label: "Stay" },
  { value: "activity", label: "Activity" },
  { value: "transport", label: "Transport" },
  { value: "shopping", label: "Shopping" },
  { value: "note", label: "Note" },
];

interface NominatimResult {
  place_id: number;
  display_name: string;
  name?: string;
  lat: string;
  lon: string;
  type?: string;
}

export function PlaceDialog({ open, onClose, store, place = null, defaultDayId = null, saveAsPersonal = false }: PlaceDialogProps) {
  const { toast } = useToast();
  const timeZone = store.bundle?.trip.timezone ?? "UTC";
  const [fields, setFields] = useState<Fields>(() => initialFields(place, defaultDayId, timeZone));
  const [tab, setTab] = useState<"search" | "manual">(place ? "manual" : "search");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<NominatimResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [onlyMe, setOnlyMe] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchAbort = useRef<AbortController | null>(null);
  const id = useId();
  const isEdit = Boolean(place);
  const isPrivate = Boolean(place?._private);
  const canBePersonal = !store.isGuest;
  const modeLabel = saveAsPersonal
    ? "Save my version"
    : isPrivate
      ? "Save private place"
      : isEdit
        ? "Save changes"
        : onlyMe
          ? "Add private stop"
          : "Add stop";

  useEffect(() => {
    if (!open) return;
    setFields(initialFields(place, defaultDayId, timeZone));
    setTab(place ? "manual" : "search");
    setQuery("");
    setResults([]);
    setSearchError(null);
    setError(null);
    setOnlyMe(false);
  }, [open, place, defaultDayId, timeZone]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!open || tab !== "search" || isEdit) return;
    const text = query.trim();
    if (text.length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    const controller = new AbortController();
    searchAbort.current?.abort();
    searchAbort.current = controller;
    setSearching(true);
    setSearchError(null);
    const timer = window.setTimeout(async () => {
      try {
        const url = new URL("https://nominatim.openstreetmap.org/search");
        url.searchParams.set("format", "jsonv2");
        url.searchParams.set("q", text);
        url.searchParams.set("limit", "7");
        url.searchParams.set("addressdetails", "1");
        const response = await fetch(url, {
          signal: controller.signal,
          headers: { Accept: "application/json" },
        });
        if (!response.ok) throw new Error("Place search is unavailable right now.");
        const data = (await response.json()) as NominatimResult[];
        setResults(Array.isArray(data) ? data : []);
      } catch (caught) {
        if ((caught as Error).name === "AbortError") return;
        setSearchError("Place search is unavailable. You can still add the stop by hand.");
        setResults([]);
      } finally {
        if (!controller.signal.aborted) setSearching(false);
      }
    }, 450);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [query, tab, open, isEdit]);

  if (!open) return null;

  function chooseResult(result: NominatimResult) {
    setFields((current) => ({
      ...current,
      name: result.name || result.display_name.split(",")[0],
      address: result.display_name,
      lat: result.lat,
      lng: result.lon,
    }));
    setTab("manual");
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    const name = fields.name.trim();
    if (!name) {
      setError("Give this stop a name.");
      return;
    }
    const day = store.bundle?.days.find((item) => item.id === fields.dayId);
    let start_time: string | null = null;
    let end_time: string | null = null;
    if (fields.startTime) {
      if (!day?.date) {
        setError("Choose a day before setting a time.");
        return;
      }
      start_time = isoFromZoned(day.date, fields.startTime, timeZone);
    }
    if (fields.endTime) {
      if (!day?.date) {
        setError("Choose a day before setting an end time.");
        return;
      }
      end_time = isoFromZoned(day.date, fields.endTime, timeZone);
    }
    if (start_time && end_time && end_time < start_time) {
      setError("The end time can't be before the start time.");
      return;
    }
    const payload: PlaceInput = {
      name,
      address: fields.address.trim() || null,
      lat: fields.lat.trim() ? Number(fields.lat) : null,
      lng: fields.lng.trim() ? Number(fields.lng) : null,
      category: fields.category,
      day_id: fields.dayId || null,
      notes: fields.notes.trim() || null,
      website: fields.website.trim() || null,
      phone: fields.phone.trim() || null,
      start_time,
      end_time,
    };
    if (Number.isNaN(payload.lat) || Number.isNaN(payload.lng)) {
      setError("Latitude and longitude need to be numbers.");
      return;
    }
    setSaving(true);
    try {
      if (isEdit && place) {
        await store.updatePlace(
          place,
          { ...payload, position: place.position, day_id: fields.dayId || null },
          saveAsPersonal ? "override" : isPrivate ? "personal" : "shared",
        );
        toast(saveAsPersonal ? "Your version is saved" : isPrivate ? "Private stop saved" : "Stop updated", "success");
      } else {
        await store.addPlace(payload, onlyMe);
        toast(onlyMe ? "Private stop added" : "Stop added to the day", "success");
      }
      onClose();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't save this stop.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={isEdit ? (saveAsPersonal ? "Your version of this stop" : place?._private ? "Edit private stop" : "Edit stop") : "Add a stop"}
      description={
        saveAsPersonal
          ? "Only you will see these changes. The group plan stays as it was."
          : isPrivate
            ? "This stop is only visible to you."
            : isEdit
              ? "Changes here update the shared itinerary for everyone."
              : "Search for a place or type the details yourself."
      }
      wide
      footer={
        <>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={saving}>
            Cancel
          </button>
          {!isEdit && tab === "search" ? (
            <button type="button" className="button button--primary" onClick={() => setTab("manual")}>
              Enter details by hand
            </button>
          ) : (
            <button type="submit" form={`place-form-${id}`} className="button button--primary" disabled={saving || !store.canWrite}>
              {saving ? <LoaderCircle size={16} className="spin" /> : <Check size={16} />} {saving ? "Saving…" : modeLabel}
            </button>
          )}
        </>
      }
    >
      {!isEdit && !store.isGuest && (
        <div className="mode-tabs" role="tablist" aria-label="How to add a place">
          <button type="button" role="tab" aria-selected={tab === "search"} className={tab === "search" ? "is-active" : ""} onClick={() => setTab("search")}>
            <Search size={15} /> Search places
          </button>
          <button type="button" role="tab" aria-selected={tab === "manual"} className={tab === "manual" ? "is-active" : ""} onClick={() => setTab("manual")}>
            <MapPin size={15} /> Enter manually
          </button>
        </div>
      )}

      {!isEdit && tab === "search" ? (
        <div className="place-search">
          <label className="field">
            <span className="field__label"><Search size={14} /> Search OpenStreetMap</span>
            <input
              autoFocus
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Try “Mercado da Ribeira” or “Kinkaku-ji”"
            />
          </label>
          <p className="field__hint">Search runs on OpenStreetMap's Nominatim service. You can always enter a place by hand.</p>
          {searching && <p className="inline-loading"><LoaderCircle size={15} className="spin" /> Looking for places…</p>}
          {searchError && (
            <div className="inline-error">
              <span>{searchError}</span>
              <button type="button" className="text-link" onClick={() => setTab("manual")}>Enter by hand</button>
            </div>
          )}
          {!searching && !searchError && query.trim().length >= 2 && results.length === 0 && (
            <p className="quiet-note">No matches yet. Try a broader name, or enter the stop by hand.</p>
          )}
          {results.length > 0 && (
            <ul className="place-results">
              {results.map((result) => (
                <li key={result.place_id}>
                  <button type="button" className="place-result" onClick={() => chooseResult(result)}>
                    <span className="place-result__icon"><MapPin size={16} /></span>
                    <span>
                      <strong>{result.name || result.display_name.split(",")[0]}</strong>
                      <small>{result.display_name}</small>
                    </span>
                    <span className="place-result__add">Use</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : (
        <form id={`place-form-${id}`} className="dialog-form" onSubmit={submit}>
          <label className="field">
            <span className="field__label">Place name</span>
            <input
              autoFocus
              value={fields.name}
              onChange={(event) => setFields((current) => ({ ...current, name: event.target.value }))}
              placeholder="A place worth remembering"
              required
            />
          </label>
          <label className="field">
            <span className="field__label">Address</span>
            <input
              value={fields.address}
              onChange={(event) => setFields((current) => ({ ...current, address: event.target.value }))}
              placeholder="Street, neighbourhood, city"
            />
          </label>

          <fieldset className="field field--fieldset">
            <legend className="field__label">Kind of stop</legend>
            <div className="category-grid">
              {CATEGORIES.map((category) => (
                <button
                  type="button"
                  key={category.value}
                  className={`category-choice ${fields.category === category.value ? "is-active" : ""}`}
                  onClick={() => setFields((current) => ({ ...current, category: category.value }))}
                  aria-pressed={fields.category === category.value}
                >
                  <PlaceCategoryIcon category={category.value} size={16} />
                  {category.label}
                </button>
              ))}
            </div>
          </fieldset>

          <div className="field-row">
            <label className="field">
              <span className="field__label">Day</span>
              <select value={fields.dayId} onChange={(event) => setFields((current) => ({ ...current, dayId: event.target.value }))}>
                <option value="">Unscheduled</option>
                {store.bundle?.days.map((day) => (
                  <option value={day.id} key={day.id}>
                    Day {day.day_index + 1} · {day.date ?? "No date"}
                  </option>
                ))}
              </select>
            </label>
            <div className="field-row field-row--tight">
              <label className="field">
                <span className="field__label">From</span>
                <input type="time" value={fields.startTime} onChange={(event) => setFields((current) => ({ ...current, startTime: event.target.value }))} />
              </label>
              <label className="field">
                <span className="field__label">To</span>
                <input type="time" value={fields.endTime} onChange={(event) => setFields((current) => ({ ...current, endTime: event.target.value }))} />
              </label>
            </div>
          </div>

          <label className="field">
            <span className="field__label">Notes</span>
            <textarea
              rows={3}
              value={fields.notes}
              onChange={(event) => setFields((current) => ({ ...current, notes: event.target.value }))}
              placeholder="What to order, which entrance to use, why it matters…"
            />
          </label>

          <div className="field-row">
            <label className="field">
              <span className="field__label">Website</span>
              <input type="url" value={fields.website} onChange={(event) => setFields((current) => ({ ...current, website: event.target.value }))} placeholder="https://" />
            </label>
            <label className="field">
              <span className="field__label">Phone</span>
              <input type="tel" value={fields.phone} onChange={(event) => setFields((current) => ({ ...current, phone: event.target.value }))} placeholder="Optional" />
            </label>
          </div>

          <details className="advanced-fields">
            <summary>Map coordinates</summary>
            <div className="field-row">
              <label className="field">
                <span className="field__label">Latitude</span>
                <input inputMode="decimal" value={fields.lat} onChange={(event) => setFields((current) => ({ ...current, lat: event.target.value }))} placeholder="38.7223" />
              </label>
              <label className="field">
                <span className="field__label">Longitude</span>
                <input inputMode="decimal" value={fields.lng} onChange={(event) => setFields((current) => ({ ...current, lng: event.target.value }))} placeholder="-9.1393" />
              </label>
            </div>
          </details>

          {!isEdit && !store.isGuest && canBePersonal && (
            <label className="check-row check-row--privacy">
              <input type="checkbox" checked={onlyMe} onChange={(event) => setOnlyMe(event.target.checked)} />
              <span className="check-row__mark" aria-hidden="true"><UserRound size={14} /></span>
              <span>
                <strong>Only visible to me</strong>
                <small>Keep this stop out of the group plan. You can still see and edit it yourself.</small>
              </span>
            </label>
          )}

          {saveAsPersonal && (
            <p className="personal-callout">
              <UserRound size={16} />
              This saves a personal version over the shared stop. Everyone else keeps seeing the original.
            </p>
          )}
          {store.offline && <p className="form-error">You're offline. Reconnect to save changes.</p>}
          {error && <p className="form-error" role="alert">{error}</p>}
        </form>
      )}

      {(!isEdit && tab === "search") && (
        <div className="dialog-inline-actions">
          <button type="button" className="text-link" onClick={() => setTab("manual")}>
            <ArrowLeft size={14} /> I'll enter it by hand
          </button>
        </div>
      )}
    </Dialog>
  );
}
