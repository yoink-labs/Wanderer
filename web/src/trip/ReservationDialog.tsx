import { Check, LoaderCircle, Plane, UserRound } from "lucide-react";
import { useEffect, useId, useState } from "react";
import { Dialog } from "../components/Dialog";
import { ReservationTypeIcon } from "../components/TripBits";
import { useToast } from "../components/Toast";
import { dateKeyInZone, fromLocalInput, localInputValue, timezoneOptions } from "../lib/dates";
import type { Reservation, ReservationInput, ReservationType } from "../types";
import type { TripStore } from "./useTripStore";

const TYPES: ReservationType[] = ["flight", "lodging", "car", "restaurant", "train", "other"];

interface ReservationDialogProps {
  open: boolean;
  onClose: () => void;
  store: TripStore;
  reservation?: Reservation | null;
  saveAsPersonal?: boolean;
}

interface Fields {
  type: ReservationType;
  title: string;
  provider: string;
  confirmation: string;
  startAt: string;
  endAt: string;
  startLocation: string;
  endLocation: string;
  cost: string;
  currency: string;
  notes: string;
  flightNumber: string;
  flightDate: string;
}

function initialFields(reservation: Reservation | null | undefined, timeZone: string, currency: string): Fields {
  const metadata = reservation?.metadata ?? {};
  return {
    type: reservation?.type ?? "flight",
    title: reservation?.title ?? "",
    provider: reservation?.provider ?? "",
    confirmation: reservation?.confirmation_code ?? "",
    startAt: localInputValue(reservation?.start_at, timeZone),
    endAt: localInputValue(reservation?.end_at, timeZone),
    startLocation: reservation?.start_location ?? "",
    endLocation: reservation?.end_location ?? "",
    cost: reservation?.cost != null ? String(reservation.cost) : "",
    currency: reservation?.currency ?? currency,
    notes: reservation?.notes ?? "",
    flightNumber: typeof metadata.flight_number === "string" ? metadata.flight_number : "",
    flightDate: typeof metadata.flight_date === "string" ? metadata.flight_date : "",
  };
}

export function ReservationDialog({ open, onClose, store, reservation = null, saveAsPersonal = false }: ReservationDialogProps) {
  const { toast } = useToast();
  const timeZone = store.bundle?.trip.timezone ?? "UTC";
  const currency = store.bundle?.trip.currency ?? "USD";
  const [fields, setFields] = useState<Fields>(() => initialFields(reservation, timeZone, currency));
  const [onlyMe, setOnlyMe] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const formId = useId();
  const isEdit = Boolean(reservation);
  const isPrivate = Boolean(reservation?._private);

  useEffect(() => {
    if (!open) return;
    setFields(initialFields(reservation, timeZone, currency));
    setOnlyMe(false);
    setError(null);
  }, [open, reservation, timeZone, currency]);

  if (!open) return null;

  function patchField<K extends keyof Fields>(key: K, value: Fields[K]) {
    setFields((current) => ({ ...current, [key]: value }));
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    const title = fields.title.trim() || (fields.type === "flight" ? fields.flightNumber.trim().toUpperCase() : "");
    if (!title) {
      setError(fields.type === "flight" ? "Add a flight number or a title." : "Give this booking a title.");
      return;
    }
    const cost = fields.cost.trim() ? Number(fields.cost) : null;
    if (cost != null && (!Number.isFinite(cost) || cost < 0)) {
      setError("The cost needs to be zero or more.");
      return;
    }
    let metadata = { ...(reservation?.metadata ?? {}) } as Record<string, unknown>;
    if (fields.type === "flight") {
      if (fields.flightNumber.trim()) metadata.flight_number = fields.flightNumber.trim().toUpperCase().replace(/[\s-]/g, "");
      else delete metadata.flight_number;
      if (fields.flightDate) metadata.flight_date = fields.flightDate;
      else if (reservation?.metadata?.flight_date) delete metadata.flight_date;
    } else {
      delete metadata.flight_number;
      delete metadata.flight_date;
    }
    const startAt = fromLocalInput(fields.startAt, timeZone);
    let endAt = fromLocalInput(fields.endAt, timeZone);
    if (startAt && endAt && endAt < startAt) {
      setError("The end time can't be before the start.");
      return;
    }
    if (!endAt && startAt && (fields.type === "lodging" || fields.type === "car")) {
      endAt = new Date(new Date(startAt).getTime() + 24 * 3600 * 1000).toISOString();
    }
    const payload: ReservationInput = {
      type: fields.type,
      title,
      provider: fields.provider.trim() || null,
      confirmation_code: fields.confirmation.trim() || null,
      start_at: startAt,
      end_at: endAt,
      start_location: fields.startLocation.trim() || null,
      end_location: fields.endLocation.trim() || null,
      cost,
      currency: fields.currency.trim().toUpperCase() || currency,
      notes: fields.notes.trim() || null,
      metadata,
    };
    setSaving(true);
    try {
      if (isEdit && reservation) {
        await store.updateReservation(
          reservation,
          payload,
          saveAsPersonal ? "override" : isPrivate ? "personal" : "shared",
        );
        toast(saveAsPersonal ? "Your booking version is saved" : isPrivate ? "Private booking saved" : "Booking updated", "success");
      } else {
        await store.addReservation(payload, onlyMe);
        toast(onlyMe ? "Private booking added" : "Booking added", "success");
      }
      onClose();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't save this booking.");
    } finally {
      setSaving(false);
    }
  }

  const currencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "SEK", "NOK", "ISK", "MXN", "BRL", "SGD", "THB", "INR"];

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={isEdit ? (saveAsPersonal ? "Your version of this booking" : isPrivate ? "Edit private booking" : "Edit booking") : "Add a booking"}
      description={
        saveAsPersonal
          ? "Only you see this version. The shared booking stays untouched."
          : isPrivate
            ? "This booking is only visible to you."
            : isEdit
              ? "Changes update the shared trip for everyone."
              : "Flights, stays, cars and reservations, kept with the day they belong to."
      }
      wide
      footer={
        <>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={saving}>Cancel</button>
          <button type="submit" form={`reservation-form-${formId}`} className="button button--primary" disabled={saving || !store.canWrite}>
            {saving ? <LoaderCircle size={16} className="spin" /> : <Check size={16} />}
            {saving ? "Saving…" : saveAsPersonal ? "Save my version" : isPrivate ? "Save private booking" : isEdit ? "Save changes" : onlyMe ? "Add private booking" : "Add booking"}
          </button>
        </>
      }
    >
      <form id={`reservation-form-${formId}`} className="dialog-form" onSubmit={submit}>
        <fieldset className="field field--fieldset">
          <legend className="field__label">Type</legend>
          <div className="category-grid category-grid--tiptype">
            {TYPES.map((type) => (
              <button
                type="button"
                key={type}
                className={`category-choice ${fields.type === type ? "is-active" : ""}`}
                onClick={() => patchField("type", type)}
                aria-pressed={fields.type === type}
              >
                <ReservationTypeIcon type={type} size={16} />
                {type === "lodging" ? "Stay" : type[0].toUpperCase() + type.slice(1)}
              </button>
            ))}
          </div>
        </fieldset>

        <label className="field">
          <span className="field__label">Title</span>
          <input
            autoFocus
            value={fields.title}
            onChange={(event) => patchField("title", event.target.value)}
            placeholder={fields.type === "flight" ? "JAL 12 · HND to ITM" : fields.type === "lodging" ? "A quiet room by the river" : "What's booked?"}
          />
        </label>

        {fields.type === "flight" && (
          <div className="flight-fields">
            <div className="flight-fields__mark"><Plane size={17} /></div>
            <div className="field-row">
              <label className="field">
                <span className="field__label">Flight number</span>
                <input
                  value={fields.flightNumber}
                  onChange={(event) => patchField("flightNumber", event.target.value.toUpperCase())}
                  placeholder="BA 12"
                  autoComplete="off"
                  spellCheck={false}
                />
              </label>
              <label className="field">
                <span className="field__label">Local flight date</span>
                <input type="date" value={fields.flightDate} onChange={(event) => patchField("flightDate", event.target.value)} />
              </label>
            </div>
            <p className="field__hint">Used for the live status lookup. AeroDataBox supplies gate, terminal and delay data.</p>
          </div>
        )}

        <div className="field-row">
          <label className="field">
            <span className="field__label">Provider</span>
            <input value={fields.provider} onChange={(event) => patchField("provider", event.target.value)} placeholder="JAL, Airbnb, JR East…" />
          </label>
          <label className="field">
            <span className="field__label">Confirmation</span>
            <input value={fields.confirmation} onChange={(event) => patchField("confirmation", event.target.value)} placeholder="ABC123" spellCheck={false} />
          </label>
        </div>

        <div className="field-row">
          <label className="field">
            <span className="field__label">Start</span>
            <input type="datetime-local" value={fields.startAt} onChange={(event) => patchField("startAt", event.target.value)} />
          </label>
          <label className="field">
            <span className="field__label">End</span>
            <input type="datetime-local" value={fields.endAt} onChange={(event) => patchField("endAt", event.target.value)} />
          </label>
        </div>
        <p className="field__hint">Times use the trip's timezone: {timeZone}.</p>

        <div className="field-row">
          <label className="field">
            <span className="field__label">From</span>
            <input value={fields.startLocation} onChange={(event) => patchField("startLocation", event.target.value)} placeholder="HND, or the hotel address" />
          </label>
          <label className="field">
            <span className="field__label">To</span>
            <input value={fields.endLocation} onChange={(event) => patchField("endLocation", event.target.value)} placeholder="ITM, or the next stop" />
          </label>
        </div>

        <div className="field-row">
          <label className="field">
            <span className="field__label">Cost</span>
            <input inputMode="decimal" value={fields.cost} onChange={(event) => patchField("cost", event.target.value)} placeholder="0" />
          </label>
          <label className="field field--currency">
            <span className="field__label">Currency</span>
            <select value={fields.currency} onChange={(event) => patchField("currency", event.target.value)}>
              {currencies.map((code) => <option value={code} key={code}>{code}</option>)}
            </select>
          </label>
        </div>

        <label className="field">
          <span className="field__label">Notes</span>
          <textarea rows={3} value={fields.notes} onChange={(event) => patchField("notes", event.target.value)} placeholder="Check-in time, baggage, seat…" />
        </label>

        {!isEdit && !store.isGuest && (
          <label className="check-row check-row--privacy">
            <input type="checkbox" checked={onlyMe} onChange={(event) => setOnlyMe(event.target.checked)} />
            <span className="check-row__mark" aria-hidden="true"><UserRound size={14} /></span>
            <span>
              <strong>Only visible to me</strong>
              <small>This booking stays in your personal layer. The group won't see it.</small>
            </span>
          </label>
        )}
        {saveAsPersonal && (
          <p className="personal-callout"><UserRound size={16} /> This saves a personal version over the shared booking.</p>
        )}
        {store.offline && <p className="form-error">You're offline. Reconnect to save changes.</p>}
        {error && <p className="form-error" role="alert">{error}</p>}
      </form>
    </Dialog>
  );
}
