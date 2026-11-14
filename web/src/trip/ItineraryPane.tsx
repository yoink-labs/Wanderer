import {
  ArrowDown,
  ArrowUp,
  Check,
  ChevronDown,
  ChevronRight,
  Clock3,
  ExternalLink,
  EyeOff,
  MapPin,
  Pencil,
  Plus,
  RotateCcw,
  StickyNote,
  UserRound,
} from "lucide-react";
import { forwardRef, useEffect, useRef, useState } from "react";
import { ConfirmDialog, Dialog } from "../components/Dialog";
import { Menu, type MenuEntry } from "../components/Menu";
import { useToast } from "../components/Toast";
import { OnlyYouBadge, PlaceCategoryIcon, ReservationTypeIcon } from "../components/TripBits";
import { dateKeyInZone, fmtDate, fmtDateLong, timeRangeInZone, weekday } from "../lib/dates";
import { googleMapsUrl } from "../lib/exports";
import { categoryLabels, money, summaryName } from "../lib/format";
import type { Place, Reservation, TripDay } from "../types";
import { flightsForReservation, type TripStore } from "./useTripStore";

interface ItineraryPaneProps {
  store: TripStore;
  selectedDayId: string | null;
  onSelectDay: (dayId: string | null, options?: { scroll?: boolean }) => void;
  selectedPlaceId: string | null;
  onSelectPlace: (placeId: string) => void;
  onAddPlace: (dayId: string | null) => void;
  onEditPlace: (place: Place, personal: boolean) => void;
  onEditReservation: (reservation: Reservation, personal: boolean) => void;
  onOpenOnlyYou: () => void;
}

export function ItineraryPane({
  store,
  selectedDayId,
  onSelectDay,
  selectedPlaceId,
  onSelectPlace,
  onAddPlace,
  onEditPlace,
  onEditReservation,
  onOpenOnlyYou,
}: ItineraryPaneProps) {
  const days = store.bundle?.days ?? [];
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const [movePlace, setMovePlace] = useState<Place | null>(null);
  const [moveDayId, setMoveDayId] = useState<string>("");
  const [pendingDelete, setPendingDelete] = useState<Place | null>(null);
  const [pendingBookingDelete, setPendingBookingDelete] = useState<Reservation | null>(null);
  const [busy, setBusy] = useState(false);
  const previousDayId = useRef<string | null>(null);
  const rowRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const { toast } = useToast();
  const timezone = store.bundle?.trip.timezone ?? "UTC";

  useEffect(() => {
    if (!selectedDayId) return;
    // Initial selection should not scroll the page past the trip header.
    const shouldScroll = previousDayId.current !== null;
    previousDayId.current = selectedDayId;
    if (selectedDayId === "unscheduled") {
      if (shouldScroll) document.getElementById("itinerary-unscheduled")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    setCollapsed((current) => {
      const next = new Set(current);
      next.delete(selectedDayId);
      return next;
    });
    if (shouldScroll) document.getElementById(`itinerary-${selectedDayId}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [selectedDayId]);

  useEffect(() => {
    if (!selectedPlaceId) return;
    const node = rowRefs.current[selectedPlaceId];
    if (node) node.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [selectedPlaceId]);

  function toggle(dayId: string) {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(dayId)) next.delete(dayId);
      else next.add(dayId);
      return next;
    });
  }

  async function run(action: () => Promise<void>, success?: string) {
    try {
      await action();
      if (success) toast(success, "success");
      return true;
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Something went wrong.", "error");
      return false;
    }
  }

  function openMove(place: Place) {
    setMovePlace(place);
    setMoveDayId(place.day_id ?? "");
  }

  async function saveMove() {
    if (!movePlace) return;
    setBusy(true);
    const ok = await run(() => store.movePlaceToDay(movePlace, moveDayId || null), "Stop moved");
    setBusy(false);
    if (ok) {
      setMovePlace(null);
      if (moveDayId) onSelectDay(moveDayId);
    }
  }

  const unscheduled = store.places.filter((place) => !place.day_id);
  const bookingsWithoutDate = store.reservations.filter((reservation) => !reservation.start_at);

  return (
    <section className="itinerary-pane" aria-label="Itinerary">
      {days.length === 0 && (
        <div className="day-section day-section--empty">
          <StickyNote size={20} />
          <div>
            <h3>No days in this trip yet</h3>
            <p>Add start and end dates in the trip settings to lay out the days.</p>
          </div>
        </div>
      )}

      {days.map((day) => {
        const dayPlaces = store.places.filter((place) => place.day_id === day.id);
        const dayReservations = store.reservations.filter((reservation) => reservation.start_at && dateKeyInZone(reservation.start_at, timezone) === day.date);
        const isCollapsed = collapsed.has(day.id);
        const mapUrl = googleMapsUrl(dayPlaces);
        return (
          <section
            className={`day-section ${selectedDayId === day.id ? "is-focused" : ""}`}
            id={`itinerary-${day.id}`}
            key={day.id}
            aria-labelledby={`day-heading-${day.id}`}
          >
            <header className="day-section__header">
              <button
                type="button"
                className="day-section__collapse"
                onClick={() => toggle(day.id)}
                aria-expanded={!isCollapsed}
                aria-label={`${isCollapsed ? "Expand" : "Collapse"} day ${day.day_index + 1}`}
              >
                <span className="day-section__index">{String(day.day_index + 1).padStart(2, "0")}</span>
                <span className="day-section__heading">
                  <span className="day-section__date">{weekday(day.date)} · {fmtDate(day.date, { month: "long", day: "numeric" })}</span>
                  <span className="day-section__title" id={`day-heading-${day.id}`}>{day.title || `Day ${day.day_index + 1}`}</span>
                </span>
                {dayPlaces.length + dayReservations.length > 0 && (
                  <span className="day-section__summary">
                    {dayPlaces.length + dayReservations.length} {dayPlaces.length + dayReservations.length === 1 ? "plan" : "plans"}
                  </span>
                )}
                {isCollapsed ? <ChevronRight size={18} /> : <ChevronDown size={18} />}
              </button>
              <div className="day-section__tools">
                {mapUrl ? (
                  <a
                    className="icon-button icon-button--quiet"
                    href={mapUrl}
                    target="_blank"
                    rel="noreferrer"
                    title="Open this day in Google Maps"
                    aria-label="Open this day in Google Maps"
                  >
                    <ExternalLink size={16} />
                  </a>
                ) : (
                  <span className="icon-button icon-button--quiet is-disabled" title="Add two places with coordinates for a route">
                    <ExternalLink size={16} />
                  </span>
                )}
                <button
                  type="button"
                  className="icon-button icon-button--quiet"
                  onClick={() => onAddPlace(day.id)}
                  disabled={!store.canWrite}
                  title="Add a stop to this day"
                  aria-label={`Add a stop to day ${day.day_index + 1}`}
                >
                  <Plus size={17} />
                </button>
              </div>
            </header>

            {!isCollapsed && (dayPlaces.length + dayReservations.length > 0 || selectedDayId === day.id) && (
              <div className="day-section__body">
                <DayNote store={store} day={day} />
                {dayPlaces.length === 0 && dayReservations.length === 0 ? (
                  <div className="day-empty">
                    <span className="day-empty__line" aria-hidden="true" />
                    <p>Nothing pinned yet. Give the day a shape.</p>
                    <button type="button" className="button button--secondary button--small" onClick={() => onAddPlace(day.id)} disabled={!store.canWrite}>
                      <Plus size={15} /> Add the first stop
                    </button>
                  </div>
                ) : (
                  <div className="stop-list">
                    {dayPlaces.map((place, index) => (
                      <PlaceRow
                        key={place.id}
                        place={place}
                        index={index}
                        store={store}
                        day={day}
                        selected={selectedPlaceId === place.id}
                        ref={(node) => { rowRefs.current[place.id] = node; }}
                        onSelect={() => onSelectPlace(place.id)}
                        onEdit={onEditPlace}
                        onMove={() => openMove(place)}
                        onDelete={() => setPendingDelete(place)}
                        onOpenOnlyYou={onOpenOnlyYou}
                        onRun={run}
                      />
                    ))}
                    {dayReservations.map((reservation) => (
                      <BookingRow
                        key={reservation.id}
                        reservation={reservation}
                        store={store}
                        onEdit={onEditReservation}
                        onDelete={() => setPendingBookingDelete(reservation)}
                        onOpenOnlyYou={onOpenOnlyYou}
                        onRun={run}
                      />
                    ))}
                    {dayPlaces.length > 0 && (
                      <button type="button" className="add-stop-row" onClick={() => onAddPlace(day.id)} disabled={!store.canWrite}>
                        <Plus size={16} /> Add another stop
                      </button>
                    )}
                  </div>
                )}
              </div>
            )}
          </section>
        );
      })}

      {(unscheduled.length > 0 || bookingsWithoutDate.length > 0 || selectedDayId === "unscheduled") && (
        <section className="day-section day-section--unscheduled" id="itinerary-unscheduled">
          <header className="day-section__header">
            <div className="day-section__collapse day-section__collapse--static">
              <span className="day-section__index"><StickyNote size={16} /></span>
              <span className="day-section__heading">
                <span className="day-section__date">Not scheduled yet</span>
                <span className="day-section__title">Ideas & loose ends</span>
              </span>
              <span className="day-section__summary">{unscheduled.length + bookingsWithoutDate.length}</span>
              <ChevronDown size={18} />
            </div>
            <div className="day-section__tools">
              <button type="button" className="icon-button icon-button--quiet" onClick={() => onAddPlace(null)} disabled={!store.canWrite} title="Add an unscheduled stop">
                <Plus size={17} />
              </button>
            </div>
          </header>
          <div className="day-section__body">
            {unscheduled.length === 0 && bookingsWithoutDate.length === 0 ? (
              <div className="day-empty">
                <p>Ideas you're not ready to place can live here.</p>
              </div>
            ) : (
              <div className="stop-list">
                {unscheduled.map((place, index) => (
                  <PlaceRow
                    key={place.id}
                    place={place}
                    index={index}
                    store={store}
                    day={null}
                    selected={selectedPlaceId === place.id}
                    ref={(node) => { rowRefs.current[place.id] = node; }}
                    onSelect={() => onSelectPlace(place.id)}
                    onEdit={onEditPlace}
                    onMove={() => openMove(place)}
                    onDelete={() => setPendingDelete(place)}
                    onOpenOnlyYou={onOpenOnlyYou}
                    onRun={run}
                  />
                ))}
                {bookingsWithoutDate.map((reservation) => (
                  <BookingRow
                    key={reservation.id}
                    reservation={reservation}
                    store={store}
                    onEdit={onEditReservation}
                    onDelete={() => setPendingBookingDelete(reservation)}
                    onOpenOnlyYou={onOpenOnlyYou}
                    onRun={run}
                  />
                ))}
              </div>
            )}
          </div>
        </section>
      )}

      <Dialog
        open={Boolean(movePlace)}
        onClose={() => setMovePlace(null)}
        title="Move this stop"
        description={movePlace ? `Where should “${movePlace.name}” sit?` : undefined}
        footer={
          <>
            <button type="button" className="button button--secondary" onClick={() => setMovePlace(null)} disabled={busy}>Cancel</button>
            <button type="button" className="button button--primary" onClick={() => void saveMove()} disabled={busy}>{busy ? "Moving…" : "Move stop"}</button>
          </>
        }
      >
        <label className="field">
          <span className="field__label">Day</span>
          <select value={moveDayId} onChange={(event) => setMoveDayId(event.target.value)}>
            <option value="">Ideas, without a day</option>
            {days.map((day) => (
              <option value={day.id} key={day.id}>Day {day.day_index + 1} · {fmtDate(day.date, { weekday: "short", month: "short", day: "numeric" })}</option>
            ))}
          </select>
        </label>
      </Dialog>

      <ConfirmDialog
        open={Boolean(pendingDelete)}
        onClose={() => setPendingDelete(null)}
        title={pendingDelete?._private ? "Delete this private stop?" : "Remove this stop?"}
        message={pendingDelete ? `${pendingDelete.name} will be removed ${pendingDelete._private ? "from your private layer" : "for everyone on the trip"}.` : ""}
        confirmLabel="Remove stop"
        destructive
        busy={busy}
        onConfirm={async () => {
          if (!pendingDelete) return;
          setBusy(true);
          const ok = await run(() => store.deletePlace(pendingDelete, pendingDelete._private ? "personal" : "shared"), "Stop removed");
          setBusy(false);
          if (ok) setPendingDelete(null);
        }}
      />
      <ConfirmDialog
        open={Boolean(pendingBookingDelete)}
        onClose={() => setPendingBookingDelete(null)}
        title={pendingBookingDelete?._private ? "Delete this private booking?" : "Remove this booking?"}
        message={pendingBookingDelete ? `${pendingBookingDelete.title} will be removed ${pendingBookingDelete._private ? "from your private layer" : "for everyone on the trip"}.` : ""}
        confirmLabel="Remove booking"
        destructive
        busy={busy}
        onConfirm={async () => {
          if (!pendingBookingDelete) return;
          setBusy(true);
          const ok = await run(() => store.deleteReservation(pendingBookingDelete, pendingBookingDelete._private ? "personal" : "shared"), "Booking removed");
          setBusy(false);
          if (ok) setPendingBookingDelete(null);
        }}
      />
    </section>
  );
}

function DayNote({ store, day }: { store: TripStore; day: TripDay }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(day.notes ?? "");
  const [saving, setSaving] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    setDraft(day.notes ?? "");
  }, [day.notes]);

  async function save() {
    if (draft === (day.notes ?? "")) {
      setEditing(false);
      return;
    }
    setSaving(true);
    try {
      await store.updateDayNotes(day.id, draft);
      setEditing(false);
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't save the note.", "error");
    } finally {
      setSaving(false);
    }
  }

  if (editing) {
    return (
      <div className="day-note day-note--editing">
        <StickyNote size={15} />
        <textarea
          autoFocus
          rows={2}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              setDraft(day.notes ?? "");
              setEditing(false);
            }
            if ((event.metaKey || event.ctrlKey) && event.key === "Enter") void save();
          }}
          placeholder="A note for the day…"
        />
        <div className="day-note__actions">
          <button type="button" className="text-link" onClick={() => { setDraft(day.notes ?? ""); setEditing(false); }}>Cancel</button>
          <button type="button" className="button button--ink button--small" onClick={() => void save()} disabled={saving}>{saving ? "Saving…" : "Save note"}</button>
        </div>
      </div>
    );
  }

  return (
    <button
      type="button"
      className={`day-note ${day.notes ? "has-note" : ""}`}
      onClick={() => store.canWrite && setEditing(true)}
      disabled={!store.canWrite}
      title={store.canWrite ? "Edit the day note" : undefined}
    >
      <StickyNote size={15} />
      <span>{day.notes || (store.canWrite ? "Add a note for the day" : "No note for this day")}</span>
      {store.canWrite && <Pencil size={13} className="day-note__pencil" />}
    </button>
  );
}

interface PlaceRowProps {
  place: Place;
  index: number;
  store: TripStore;
  day: TripDay | null;
  selected: boolean;
  onSelect: () => void;
  onEdit: (place: Place, personal: boolean) => void;
  onMove: () => void;
  onDelete: () => void;
  onOpenOnlyYou: () => void;
  onRun: (action: () => Promise<void>, success?: string) => Promise<boolean>;
}

const PlaceRow = forwardRef<HTMLDivElement, PlaceRowProps>(function PlaceRow(
  { place, index, store, selected, onSelect, onEdit, onMove, onDelete, onRun },
  ref,
) {
    const { toast } = useToast();
    const timeZone = store.bundle?.trip.timezone ?? "UTC";
    const time = timeRangeInZone(place.start_time, place.end_time, timeZone);
    const expenses = store.bundle?.expenses.filter((expense) => expense.place_id === place.id) ?? [];
    const cost = expenses.reduce((sum, expense) => sum + expense.amount, 0);
    const privateItem = Boolean(place._private);
    const overridden = Boolean(place._overridden);
    const menuEntries: MenuEntry[] = [
      {
        label: privateItem ? "Edit private details" : "Edit details",
        icon: <Pencil size={15} />,
        onSelect: () => onEdit(place, false),
        disabled: !store.canWrite,
      },
      ...(!store.isGuest && !privateItem ? [
        {
          label: "Save my version",
          icon: <UserRound size={15} />,
          detail: "Only you see the changes",
          onSelect: () => onEdit(place, true),
          disabled: !store.canWrite,
        } as MenuEntry,
        {
          label: "Hide for me",
          icon: <EyeOff size={15} />,
          detail: "Keep the shared stop for everyone else",
          onSelect: () => void onRun(() => store.hidePersonal("place", place.id, true), "Hidden from your plan"),
          disabled: !store.canWrite,
        } as MenuEntry,
        ...(overridden ? [{
          label: "Restore shared version",
          icon: <RotateCcw size={15} />,
          onSelect: () => void onRun(() => store.restorePersonal("place", place.id), "Shared version restored"),
          disabled: !store.canWrite,
        } as MenuEntry] : []),
      ] : []),
      { separator: true },
      {
        label: "Move up",
        icon: <ArrowUp size={15} />,
        onSelect: () => void onRun(() => store.movePlace(place, "up")),
        disabled: !store.canWrite || index === 0,
      },
      {
        label: "Move down",
        icon: <ArrowDown size={15} />,
        onSelect: () => void onRun(() => store.movePlace(place, "down")),
        disabled: !store.canWrite,
      },
      {
        label: "Move to another day…",
        icon: <ChevronRight size={15} />,
        onSelect: onMove,
        disabled: !store.canWrite,
      },
      { separator: true },
      {
        label: privateItem ? "Delete private stop" : "Remove from trip",
        onSelect: onDelete,
        danger: true,
        disabled: !store.canWrite,
      },
    ];

    return (
      <div
        ref={ref}
        className={`place-row ${selected ? "is-selected" : ""} ${place.visited_at ? "is-visited" : ""} ${privateItem ? "is-private" : ""}`}
        data-place-id={place.id}
      >
        <span className="place-row__route" aria-hidden="true">
          <span className="place-row__number">{index + 1}</span>
        </span>
        <div
          className="place-row__main"
          role="button"
          tabIndex={0}
          onClick={onSelect}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              onSelect();
            }
          }}
          aria-label={`${place.name}${time ? `, ${time}` : ""}${place.address ? `, ${place.address}` : ""}. Select on map.`}
        >
          <div className="place-row__top">
            <span className="place-row__category" title={categoryLabels[place.category]}>
              <PlaceCategoryIcon category={place.category} size={15} />
            </span>
            <h3>{place.name}</h3>
            {privateItem && <OnlyYouBadge />}
            {overridden && <OnlyYouBadge label="Your version" title="You saved a personal version of this shared stop" />}
            {place.rating != null && <span className="rating">{place.rating.toFixed(1)}</span>}
            {cost > 0 && <span className="place-row__cost">{money(cost, store.bundle?.trip.currency)}</span>}
          </div>
          <div className="place-row__meta">
            {time && <span className="time-chip"><Clock3 size={12} /> {time}</span>}
            {place.address && <span className="place-row__address">{place.address}</span>}
          </div>
          {place.notes && <p className="place-row__notes">{place.notes}</p>}
        </div>
        <div className="place-row__actions">
          <button
            type="button"
            className={`visit-toggle ${place.visited_at ? "is-checked" : ""}`}
            onClick={() => {
              void store
                .setVisited(place, !place.visited_at)
                .then(() => toast(place.visited_at ? "Marked not visited" : "Marked visited", "success"))
                .catch((caught) => toast(caught instanceof Error ? caught.message : "Couldn't update the stop.", "error"));
            }}
            disabled={!store.canWrite}
            aria-pressed={Boolean(place.visited_at)}
            title={place.visited_at ? "Mark as not visited" : "Mark as visited"}
            aria-label={place.visited_at ? `Mark ${place.name} as not visited` : `Mark ${place.name} as visited`}
          >
            <Check size={14} />
          </button>
          <Menu entries={menuEntries} label={`Actions for ${place.name}`} />
        </div>
      </div>
    );
});

function BookingRow({
  reservation,
  store,
  onEdit,
  onDelete,
  onOpenOnlyYou,
  onRun,
}: {
  reservation: Reservation;
  store: TripStore;
  onEdit: (reservation: Reservation, personal: boolean) => void;
  onDelete: () => void;
  onOpenOnlyYou: () => void;
  onRun: (action: () => Promise<void>, success?: string) => Promise<boolean>;
}) {
  const lookup = flightsForReservation(store.flights, reservation.id);
  const flight = lookup?.flight;
  const timeZone = store.bundle?.trip.timezone ?? "UTC";
  const time = reservation.start_at ? timeRangeInZone(reservation.start_at, reservation.end_at, timeZone) : "";
  const date = reservation.start_at ? fmtDate(dateKeyInZone(reservation.start_at, timeZone), { weekday: "short", month: "short", day: "numeric" }) : "No date";
  const isTrouble = flight && ["Delayed", "Canceled", "CanceledUncertain", "Diverted", "GateClosed"].includes(flight.status);
  const isDone = flight && ["Arrived", "Canceled", "Diverted"].includes(flight.status);
  const privateItem = Boolean(reservation._private);
  const overridden = Boolean(reservation._overridden);
  const entries: MenuEntry[] = [
    {
      label: "Edit booking",
      icon: <Pencil size={15} />,
      onSelect: () => onEdit(reservation, false),
      disabled: !store.canWrite,
    },
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
    {
      label: privateItem ? "Delete private booking" : "Remove booking",
      onSelect: onDelete,
      danger: true,
      disabled: !store.canWrite,
    },
  ];

  return (
    <div className={`booking-row ${privateItem ? "is-private" : ""}`}>
      <span className={`booking-row__icon booking-row__icon--${reservation.type}`}>
        <ReservationTypeIcon type={reservation.type} size={16} />
      </span>
      <div className="booking-row__main">
        <div className="booking-row__top">
          <span className="booking-row__kind">{reservation.type === "lodging" ? "Stay" : reservation.type[0].toUpperCase() + reservation.type.slice(1)}</span>
          <h3>{reservation.title}</h3>
          {privateItem && <OnlyYouBadge />}
          {overridden && <OnlyYouBadge label="Your version" />}
        </div>
        <div className="booking-row__meta">
          <span>{date}</span>
          {time && <><span className="dot" /><span>{time}</span></>}
          {reservation.confirmation_code && <><span className="dot" /><span>Conf. {reservation.confirmation_code}</span></>}
        </div>
        <div className="booking-row__route">
          {reservation.start_location && <span>{reservation.start_location}</span>}
          {reservation.start_location && reservation.end_location && <span className="route-arrow" aria-hidden="true">→</span>}
          {reservation.end_location && <span>{reservation.end_location}</span>}
          {reservation.provider && <span className="booking-row__provider">{reservation.provider}</span>}
        </div>
        {flight && (
          <div className="flight-live-row">
            <span className={`flight-status ${isTrouble ? "is-trouble" : isDone ? "is-done" : "is-live"}`}>
              <span className="flight-status__dot" />
              {flight.status_label}
            </span>
            {flight.departure.delay_minutes != null && flight.departure.delay_minutes > 0 && (
              <span className="flight-delay">+{flight.departure.delay_minutes} min</span>
            )}
            {flight.departure.gate && <span className="flight-detail">Gate {flight.departure.gate}</span>}
            {flight.departure.terminal && <span className="flight-detail">Terminal {flight.departure.terminal}</span>}
            <a className="flight-attribution" href="https://aerodatabox.com" target="_blank" rel="noreferrer">
              Flight data by AeroDataBox
            </a>
          </div>
        )}
      </div>
      <div className="booking-row__side">
        {reservation.cost != null && reservation.cost > 0 && (
          <span className="booking-row__cost">{money(reservation.cost, reservation.currency ?? store.bundle?.trip.currency)}</span>
        )}
        <Menu entries={entries} label={`Actions for ${reservation.title}`} />
      </div>
    </div>
  );
}
