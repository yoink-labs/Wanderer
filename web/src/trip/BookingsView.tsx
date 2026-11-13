import { AlertTriangle, CalendarDays, EyeOff, Pencil, Plane, Plus, RotateCcw, Ticket, UserRound } from "lucide-react";
import { useEffect, useState } from "react";
import { ConfirmDialog } from "../components/Dialog";
import { Menu, type MenuEntry } from "../components/Menu";
import { useToast } from "../components/Toast";
import { OnlyYouBadge, ReservationTypeIcon } from "../components/TripBits";
import { dateKeyInZone, fmtDate, fmtDateLong, formatDuration, fmtDateRange, timeRangeInZone } from "../lib/dates";
import { money } from "../lib/format";
import type { Reservation } from "../types";
import { flightsForReservation, type TripStore } from "./useTripStore";

export function BookingsView({
  store,
  onAdd,
  onEdit,
}: {
  store: TripStore;
  onAdd: () => void;
  onEdit: (reservation: Reservation, personal: boolean) => void;
}) {
  const { toast } = useToast();
  const timezone = store.bundle?.trip.timezone ?? "UTC";
  const [pendingDelete, setPendingDelete] = useState<Reservation | null>(null);
  const [busy, setBusy] = useState(false);
  const [refreshTried, setRefreshTried] = useState(false);

  useEffect(() => {
    if (refreshTried || store.flights || store.isGuest) return;
    setRefreshTried(true);
    void store.refreshFlights();
  }, [refreshTried, store]);

  const sorted = [...store.reservations].sort((a, b) => {
    if (!a.start_at && !b.start_at) return a.title.localeCompare(b.title);
    if (!a.start_at) return 1;
    if (!b.start_at) return -1;
    return a.start_at.localeCompare(b.start_at);
  });
  const today = new Date().toISOString();
  const upcoming = sorted.filter((reservation) => !reservation.start_at || (reservation.start_at >= today && reservation.type !== "flight") || (reservation.start_at ?? "") >= today);
  const past = sorted.filter((reservation) => !upcoming.includes(reservation));
  const budget = store.flights?.budget;
  const exhausted =
    Object.values(store.flights?.flights ?? {}).some((lookup) => lookup.budget_exhausted) ||
    (budget ? budget.units_used >= budget.units_cap || budget.requests_used >= budget.requests_cap : false);

  async function deleteReservation() {
    if (!pendingDelete) return;
    setBusy(true);
    try {
      await store.deleteReservation(pendingDelete, pendingDelete._private ? "personal" : "shared");
      toast("Booking removed", "success");
      setPendingDelete(null);
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't remove this booking.", "error");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="tool-page bookings-page">
      <header className="tool-heading">
        <div>
          <p className="context-line">Tickets & confirmations</p>
          <h1>Bookings</h1>
          <p>Flights, stays and reservations, gathered on the day they happen. Private bookings stay in your pocket.</p>
        </div>
        <button type="button" className="button button--primary" onClick={onAdd} disabled={!store.canWrite}>
          <Plus size={17} /> Add booking
        </button>
      </header>

      {exhausted && (
        <div className="notice notice--warning" role="status">
          <AlertTriangle size={18} />
          <div>
            <strong>Live flight lookups are paused this month</strong>
            <p>The free AeroDataBox budget is spent. Your booking details and times are still saved; live gate and delay updates will return next month.</p>
          </div>
        </div>
      )}
      {store.flightsError && !exhausted && (
        <div className="notice">
          <Plane size={18} />
          <div>
            <strong>Live flight status isn't available right now</strong>
            <p>{store.flightsError} Your saved flight details are unaffected.</p>
          </div>
        </div>
      )}

      {sorted.length === 0 ? (
        <div className="tool-empty">
          <span><Ticket size={24} /></span>
          <h2>No tickets yet</h2>
          <p>Add the flight that gets you there, the room you're staying in, or the table you booked.</p>
          <button type="button" className="button button--primary" onClick={onAdd} disabled={!store.canWrite}>
            <Plus size={16} /> Add your first booking
          </button>
        </div>
      ) : (
        <>
          {upcoming.length > 0 && (
            <section className="booking-section" aria-labelledby="bookings-ahead">
              <div className="section-heading section-heading--compact">
                <h2 id="bookings-ahead">Ahead</h2>
                <span className="count-note">{upcoming.length} {upcoming.length === 1 ? "booking" : "bookings"}</span>
              </div>
              <div className="ticket-list">
                {upcoming.map((reservation) => (
                  <BookingTicket
                    key={reservation.id}
                    reservation={reservation}
                    store={store}
                    timezone={timezone}
                    onEdit={onEdit}
                    onDelete={() => setPendingDelete(reservation)}
                    onRun={async (action, success) => {
                      try {
                        await action();
                        if (success) toast(success, "success");
                      } catch (caught) {
                        toast(caught instanceof Error ? caught.message : "Something went wrong.", "error");
                      }
                    }}
                  />
                ))}
              </div>
            </section>
          )}
          {past.length > 0 && (
            <section className="booking-section" aria-labelledby="bookings-past">
              <div className="section-heading section-heading--compact">
                <h2 id="bookings-past">Earlier</h2>
                <span className="count-note">{past.length}</span>
              </div>
              <div className="ticket-list">
                {past.map((reservation) => (
                  <BookingTicket
                    key={reservation.id}
                    reservation={reservation}
                    store={store}
                    timezone={timezone}
                    onEdit={onEdit}
                    onDelete={() => setPendingDelete(reservation)}
                    onRun={async (action, success) => {
                      try {
                        await action();
                        if (success) toast(success, "success");
                      } catch (caught) {
                        toast(caught instanceof Error ? caught.message : "Something went wrong.", "error");
                      }
                    }}
                  />
                ))}
              </div>
            </section>
          )}
        </>
      )}

      <ConfirmDialog
        open={Boolean(pendingDelete)}
        onClose={() => setPendingDelete(null)}
        onConfirm={deleteReservation}
        title={pendingDelete?._private ? "Delete this private booking?" : "Remove this booking?"}
        message={pendingDelete ? `${pendingDelete.title} will be removed ${pendingDelete._private ? "from your private layer" : "for everyone on the trip"}.` : ""}
        confirmLabel="Remove booking"
        destructive
        busy={busy}
      />
    </div>
  );
}

function routeCodes(title: string): [string, string] | null {
  const match = /^\s*([A-Za-z]{3})\s*(?:→|->|–|-|to)\s*([A-Za-z]{3})\s*$/.exec(title);
  return match ? [match[1].toUpperCase(), match[2].toUpperCase()] : null;
}

function BookingTicket({
  reservation,
  store,
  timezone,
  onEdit,
  onDelete,
  onRun,
}: {
  reservation: Reservation;
  store: TripStore;
  timezone: string;
  onEdit: (reservation: Reservation, personal: boolean) => void;
  onDelete: () => void;
  onRun: (action: () => Promise<void>, success?: string) => Promise<void>;
}) {
  const lookup = flightsForReservation(store.flights, reservation.id);
  const flight = lookup?.flight;
  const codes = routeCodes(reservation.title);
  // Manual bookings often carry "LHR" in the route fields without an
  // "LHR → LIS" title. Use those as the big mark instead of "From"/"To".
  const locationCode = (value?: string | null) => value?.match(/\b([A-Z]{3})\b/)?.[1] ?? null;
  const originMark = codes?.[0] ?? locationCode(reservation.start_location);
  const destinationMark = codes?.[1] ?? locationCode(reservation.end_location);
  const originPlace = reservation.start_location && reservation.start_location !== originMark ? reservation.start_location : null;
  const destinationPlace = reservation.end_location && reservation.end_location !== destinationMark ? reservation.end_location : null;
  const isStay = reservation.type === "lodging" || reservation.type === "car";
  const startTime = timeRangeInZone(reservation.start_at, reservation.end_at, timezone);
  const span = formatDuration(reservation.start_at, reservation.end_at);
  const date = reservation.start_at ? dateKeyInZone(reservation.start_at, timezone) : null;
  const isPast = Boolean(reservation.start_at && new Date(reservation.start_at).getTime() < Date.now());
  const privateItem = Boolean(reservation._private);
  const overridden = Boolean(reservation._overridden);
  const trouble = flight && ["Delayed", "Canceled", "CanceledUncertain", "Diverted", "GateClosed"].includes(flight.status);
  const done = flight && ["Arrived", "Canceled", "Diverted"].includes(flight.status);

  const entries: MenuEntry[] = [
    { label: "Edit booking", icon: <Pencil size={15} />, onSelect: () => onEdit(reservation, false), disabled: !store.canWrite },
    ...(!store.isGuest && !privateItem ? [
      {
        label: "Save my version",
        icon: <UserRound size={15} />,
        detail: "Only you see the changes",
        onSelect: () => onEdit(reservation, true),
        disabled: !store.canWrite,
      } as MenuEntry,
      {
        label: "Hide for me",
        icon: <EyeOff size={15} />,
        onSelect: () => void onRun(() => store.hidePersonal("reservation", reservation.id, true), "Booking hidden from your plan"),
        disabled: !store.canWrite,
      } as MenuEntry,
      ...(overridden ? [{
        label: "Restore shared version",
        icon: <RotateCcw size={15} />,
        onSelect: () => void onRun(() => store.restorePersonal("reservation", reservation.id), "Shared version restored"),
        disabled: !store.canWrite,
      } as MenuEntry] : []),
    ] : []),
    { separator: true },
    { label: privateItem ? "Delete private booking" : "Remove booking", onSelect: onDelete, danger: true, disabled: !store.canWrite },
  ];

  return (
    <article className={`ticket ${isPast ? "ticket--past" : ""} ${privateItem ? "ticket--private" : ""}`}>
      <div className="ticket__main">
        <header className="ticket__header">
          <span className={`ticket__kind ticket__kind--${reservation.type}`}>
            <ReservationTypeIcon type={reservation.type} size={17} />
          </span>
          <span className="ticket__type">{reservation.type === "lodging" ? "Stay" : reservation.type[0].toUpperCase() + reservation.type.slice(1)}</span>
          {privateItem && <OnlyYouBadge />}
          {overridden && <OnlyYouBadge label="Your version" />}
          {span && <span className="ticket__span">{span}</span>}
          <Menu entries={entries} label={`Actions for ${reservation.title}`} />
        </header>

        <div className="ticket__route">
          <div className="ticket__point">
            <span className="ticket__mark">{originMark ?? (isStay ? fmtDate(date, { month: "short", day: "numeric" }) : "From")}</span>
            <span className="ticket__place">{originPlace ?? (codes ? "" : reservation.provider ?? "")}</span>
            {date && <span className="ticket__time">{fmtDate(date, { weekday: "short", month: "short", day: "numeric" })}{startTime ? ` · ${startTime}` : ""}</span>}
          </div>
          <span className={`ticket__line ${isStay ? "ticket__line--stay" : ""}`} aria-hidden="true">
            <span />
            {reservation.type === "flight" ? <Plane size={14} /> : <CalendarDays size={14} />}
            <span />
          </span>
          <div className="ticket__point ticket__point--end">
            <span className="ticket__mark">
              {destinationMark ?? (reservation.end_at ? fmtDate(dateKeyInZone(reservation.end_at, timezone), { month: "short", day: "numeric" }) : "To")}
            </span>
            <span className="ticket__place">{destinationPlace ?? ""}</span>
            {reservation.end_at && <span className="ticket__time">{fmtDate(dateKeyInZone(reservation.end_at, timezone), { weekday: "short", month: "short", day: "numeric" })} · {timeRangeInZone(reservation.end_at, null, timezone)}</span>}
          </div>
        </div>

        <div className="ticket__title-row">
          <h3>{reservation.title}</h3>
          {reservation.provider && <span>{reservation.provider}</span>}
        </div>

        {flight && (
          <div className="flight-live">
            <span className={`flight-status ${trouble ? "is-trouble" : done ? "is-done" : "is-live"}`}>
              <span className="flight-status__dot" />
              {flight.status_label}
            </span>
            {flight.departure.delay_minutes != null && flight.departure.delay_minutes > 0 && <span className="flight-delay">+{flight.departure.delay_minutes} min</span>}
            {flight.departure.gate && <span className="flight-detail">Gate {flight.departure.gate}</span>}
            {flight.departure.terminal && <span className="flight-detail">Terminal {flight.departure.terminal}</span>}
            {flight.aircraft && <span className="flight-detail">{flight.aircraft}</span>}
            <a className="flight-attribution" href="https://aerodatabox.com" target="_blank" rel="noreferrer">Flight data by AeroDataBox</a>
          </div>
        )}
        {lookup?.stale && flight && <p className="ticket__stale">Showing the last known status.</p>}
      </div>

      <div className="ticket__stub">
        <div>
          <span className="ticket__stub-label">Confirmation</span>
          <span className="ticket__code">{reservation.confirmation_code || "Not added"}</span>
        </div>
        {reservation.cost != null && reservation.cost > 0 && (
          <span className="ticket__cost">{money(reservation.cost, reservation.currency ?? store.bundle?.trip.currency)}</span>
        )}
        {reservation.notes && <p className="ticket__notes">{reservation.notes}</p>}
      </div>
    </article>
  );
}
