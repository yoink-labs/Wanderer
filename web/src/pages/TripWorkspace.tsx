import {
  AlertTriangle,
  ArrowLeft,
  CalendarDays,
  CloudOff,
  Download,
  Eye,
  ListChecks,
  Map,
  MapPin,
  MoreHorizontal,
  NotebookPen,
  Pencil,
  Plus,
  Printer,
  RefreshCw,
  Settings2,
  Share2,
  Ticket,
  UserRound,
  Wallet,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, NavLink, useNavigate, useParams } from "react-router-dom";
import { useSession } from "../auth/session";
import { AvatarStack } from "../components/Avatar";
import { CoverArt } from "../components/CoverArt";
import { ConfirmDialog, Dialog } from "../components/Dialog";
import { Menu, type MenuEntry } from "../components/Menu";
import { ErrorState, TripSkeleton } from "../components/States";
import { useToast } from "../components/Toast";
import { countdownLabel, estimatedTimezone, fmtDate, fmtDateLong, fmtDateRange, timezoneOptions } from "../lib/dates";
import { calendarFileForBundle, downloadText, googleMapsUrl } from "../lib/exports";
import { money, plural, summaryName } from "../lib/format";
import { BookingsView } from "../trip/BookingsView";
import { BudgetView } from "../trip/BudgetView";
import { ChecklistView } from "../trip/ChecklistView";
import { DayRail } from "../trip/DayRail";
import { ItineraryPane } from "../trip/ItineraryPane";
import { MapPane } from "../trip/MapPane";
import { NotesView } from "../trip/NotesView";
import { OnlyYouPanel } from "../trip/OnlyYouPanel";
import { PlaceDialog } from "../trip/PlaceDialog";
import { ReservationDialog } from "../trip/ReservationDialog";
import { ShareView } from "../trip/ShareView";
import { useTripStore } from "../trip/useTripStore";
import type { Place, Reservation } from "../types";

const TOOLS = new Set(["plan", "bookings", "budget", "checklist", "notes", "share"]);

const TABS = [
  { id: "plan", label: "Plan", icon: Map },
  { id: "bookings", label: "Bookings", icon: Ticket },
  { id: "budget", label: "Budget", icon: Wallet },
  { id: "checklist", label: "Checklist", icon: ListChecks },
  { id: "notes", label: "Notes", icon: NotebookPen },
];

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "SEK", "NOK", "ISK", "MXN", "BRL", "SGD", "THB", "INR"];

export default function TripWorkspace() {
  const { tripId = "", tool: rawTool } = useParams();
  const tool = TOOLS.has(rawTool ?? "") ? (rawTool as string) : "plan";
  const store = useTripStore(tripId);
  const session = useSession();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [selectedDayId, setSelectedDayId] = useState<string | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);
  // A three-pane workspace needs room for three readable columns. Below
  // ~1100px the map starts collapsed and the button brings it back, instead
  // of squeezing the itinerary into a narrow strip.
  const [mapVisible, setMapVisible] = useState(() => window.innerWidth >= 1100);
  const [mobileView, setMobileView] = useState<"itinerary" | "map">("itinerary");
  const [placeDialog, setPlaceDialog] = useState<{ open: boolean; place: Place | null; personal: boolean; dayId: string | null }>({ open: false, place: null, personal: false, dayId: null });
  const [reservationDialog, setReservationDialog] = useState<{ open: boolean; reservation: Reservation | null; personal: boolean }>({ open: false, reservation: null, personal: false });
  const [onlyYouOpen, setOnlyYouOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const initializedDay = useRef<string | null>(null);

  const trip = store.bundle?.trip;
  const days = store.bundle?.days ?? [];
  const members = store.bundle?.members ?? [];
  const memberNames = members.map((member) => summaryName(member.display_name, member.email));

  useEffect(() => {
    document.title = trip ? `${trip.title} · Wanderer` : "Wanderer";
  }, [trip]);

  useEffect(() => {
    if (!store.bundle || initializedDay.current === store.bundle.trip.id) return;
    initializedDay.current = store.bundle.trip.id;
    const today = new Date().toISOString().slice(0, 10);
    const current = store.bundle.days.find((day) => day.date === today);
    setSelectedDayId(current?.id ?? store.bundle.days[0]?.id ?? null);
  }, [store.bundle]);

  useEffect(() => {
    setPlaceDialog((current) => ({ ...current, open: false }));
    setReservationDialog((current) => ({ ...current, open: false }));
  }, [tool]);

  if (store.loading) {
    return (
      <div className="workspace-page">
        <div className="page-shell"><TripSkeleton /></div>
      </div>
    );
  }

  if (store.error || !trip) {
    return (
      <div className="page-shell page-shell--narrow workspace-error">
        <ErrorState
          title="Couldn't open this trip"
          message={store.error ?? "That trip wasn't found."}
          onRetry={() => void store.reload()}
        />
        <Link to="/" className="text-link"><ArrowLeft size={14} /> Back to your trips</Link>
      </div>
    );
  }

  const exportEntries: MenuEntry[] = [
    {
      label: "Print itinerary",
      icon: <Printer size={15} />,
      onSelect: () => window.print(),
    },
    {
      label: "Download calendar",
      icon: <Download size={15} />,
      detail: "Timed stops and bookings (.ics)",
      onSelect: () => {
        downloadText(`${trip.title}.ics`, calendarFileForBundle({ ...store.bundle!, places: store.places, reservations: store.reservations }));
        toast("Calendar file downloaded", "success");
      },
    },
    ...(store.role !== "viewer" ? [{
      label: "Trip settings",
      icon: <Settings2 size={15} />,
      onSelect: () => setSettingsOpen(true),
    } as MenuEntry] : []),
    ...(!store.isGuest ? [{
      label: "Only you",
      icon: <UserRound size={15} />,
      onSelect: () => setOnlyYouOpen(true),
    } as MenuEntry] : []),
    { separator: true },
    ...(store.role === "owner" ? [{
      label: "Delete trip",
      icon: <AlertTriangle size={15} />,
      danger: true,
      onSelect: () => setDeleteOpen(true),
    } as MenuEntry] : []),
  ].filter((entry) => !("separator" in entry) || true) as MenuEntry[];

  const dayPlaces = selectedDayId && selectedDayId !== "unscheduled"
    ? store.places.filter((place) => place.day_id === selectedDayId)
    : store.places;
  const dayRoute = googleMapsUrl(dayPlaces);

  function selectDay(dayId: string | null, options?: { scroll?: boolean }) {
    setSelectedDayId(dayId);
    if (!options?.scroll) return;
    if (window.innerWidth < 900) setMobileView("itinerary");
  }

  function selectPlace(placeId: string) {
    setSelectedPlaceId(placeId);
    const place = store.places.find((item) => item.id === placeId);
    if (place?.day_id) setSelectedDayId(place.day_id);
    if (window.innerWidth < 900) setMobileView("itinerary");
  }

  function openAddPlace(dayId: string | null) {
    if (!store.canWrite) return;
    setPlaceDialog({ open: true, place: null, personal: false, dayId });
  }

  function openEditPlace(place: Place, personal: boolean) {
    if (!store.canWrite) return;
    setPlaceDialog({ open: true, place, personal, dayId: place.day_id });
  }

  function openAddReservation() {
    if (!store.canWrite) return;
    setReservationDialog({ open: true, reservation: null, personal: false });
  }

  function openEditReservation(reservation: Reservation, personal: boolean) {
    if (!store.canWrite) return;
    setReservationDialog({ open: true, reservation, personal });
  }

  async function deleteTrip() {
    setDeleting(true);
    try {
      await store.deleteTrip();
      toast("Trip deleted", "success");
      navigate("/");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't delete this trip.", "error");
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className={`workspace-page ${store.offline ? "is-offline" : ""}`}>
      <header className="trip-header">
        <div className="trip-header__top page-shell">
          <Link to="/" className="trip-header__back" aria-label="Back to trips">
            <ArrowLeft size={17} />
            <span>Trips</span>
          </Link>
          <div className="trip-header__identity">
            <CoverArt seed={trip.id} destination={trip.destination} imageUrl={trip.cover_url} variant="rail" showMark={false} className="trip-header__cover" />
            <div className="trip-header__copy">
              <span className="trip-header__destination">{trip.destination || "Somewhere new"}</span>
              <h1>{trip.title}</h1>
              <div className="trip-header__meta">
                <span><CalendarDays size={14} /> {fmtDateRange(trip.start_date, trip.end_date)}</span>
                <span className="dot" />
                <span>{countdownLabel(trip.start_date, trip.end_date)}</span>
              </div>
            </div>
          </div>
          <div className="trip-header__actions">
            <div className="trip-header__members" title={memberNames.join(", ")}>
              <AvatarStack names={memberNames} max={4} />
            </div>
            <Link to={`/trips/${trip.id}/share`} className="button button--primary button--small trip-header__share">
              <Share2 size={15} /> Share
            </Link>
            <Menu
              entries={exportEntries.filter((entry) => !("separator" in entry) || true)}
              label="Trip actions and exports"
              trigger={<><MoreHorizontal size={17} /><span className="sr-only">More actions</span></>}
              triggerClassName="button button--secondary button--small"
            />
          </div>
        </div>

        <nav className="trip-tabs page-shell" aria-label="Trip sections">
          <div className="trip-tabs__scroll">
            {TABS.map((tab) => {
              const Icon = tab.icon;
              const to = tab.id === "plan" ? `/trips/${trip.id}` : `/trips/${trip.id}/${tab.id}`;
              return (
                <NavLink
                  key={tab.id}
                  to={to}
                  end={tab.id === "plan"}
                  className={({ isActive }) => `trip-tab ${isActive ? "is-active" : ""}`}
                >
                  <Icon size={16} />
                  {tab.label}
                </NavLink>
              );
            })}
          </div>
          <button
            type="button"
            className={`button button--secondary button--small map-collapse-button ${!mapVisible ? "is-visible" : ""}`}
            onClick={() => setMapVisible((current) => !current)}
            aria-pressed={!mapVisible}
          >
            <Map size={15} /> {mapVisible ? "Hide map" : "Show map"}
          </button>
        </nav>
      </header>

      {(store.offline || store.role === "viewer" || store.isGuest) && (
        <div className="workspace-banners page-shell">
          {store.offline && (
            <div className="notice notice--warning" role="status">
              <CloudOff size={18} />
              <div>
                <strong>Offline — showing your saved copy</strong>
                <p>Saved {store.savedOfflineAt ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(store.savedOfflineAt)) : "earlier"}. Editing is paused until you reconnect.</p>
              </div>
              <button type="button" className="button button--secondary button--small" onClick={() => void store.reload()}>
                <RefreshCw size={14} /> Retry
              </button>
            </div>
          )}
          {store.role === "viewer" && (
            <div className="notice">
              <Eye size={18} />
              <div><strong>View only</strong><p>You can read this trip and use the map, but editing is turned off for your account.</p></div>
            </div>
          )}
          {store.isGuest && (
            <div className="notice notice--guest">
              <UserRound size={18} />
              <div><strong>Guest plan on this device</strong><p>Sign in to keep it with your account, invite people, and use the private layer.</p></div>
              <button type="button" className="button button--ink button--small" onClick={session.signIn}>Sign in</button>
            </div>
          )}
        </div>
      )}

      {tool === "plan" ? (
        <div className={`plan-layout page-shell ${!mapVisible ? "map-hidden" : ""} plan-layout--mobile-${mobileView}`}>
          <DayRail
            store={store}
            days={days}
            places={store.places}
            reservations={store.reservations}
            selectedDayId={selectedDayId}
            onSelectDay={selectDay}
            onOpenOnlyYou={() => setOnlyYouOpen(true)}
          />
          <ItineraryPane
            store={store}
            selectedDayId={selectedDayId}
            onSelectDay={selectDay}
            selectedPlaceId={selectedPlaceId}
            onSelectPlace={selectPlace}
            onAddPlace={openAddPlace}
            onEditPlace={openEditPlace}
            onEditReservation={openEditReservation}
            onOpenOnlyYou={() => setOnlyYouOpen(true)}
          />
          <MapPane
            places={store.places}
            days={days}
            focusDayId={selectedDayId}
            onFocusDay={(dayId) => setSelectedDayId(dayId)}
            selectedPlaceId={selectedPlaceId}
            onSelectPlace={selectPlace}
          />
          {dayRoute && (
            <a className="workspace-map-link" href={dayRoute} target="_blank" rel="noreferrer">
              <MapPin size={14} /> Open this day in Google Maps
            </a>
          )}
        </div>
      ) : (
        <div className="page-shell tool-shell">
          {tool === "bookings" && (
            <BookingsView store={store} onAdd={openAddReservation} onEdit={openEditReservation} />
          )}
          {tool === "budget" && <BudgetView store={store} />}
          {tool === "checklist" && <ChecklistView store={store} />}
          {tool === "notes" && <NotesView store={store} />}
          {tool === "share" && <ShareView store={store} />}
        </div>
      )}

      {tool === "plan" && (
        <div className="mobile-switch" role="group" aria-label="Switch between itinerary and map">
          <button type="button" className={mobileView === "itinerary" ? "is-active" : ""} onClick={() => setMobileView("itinerary")}>
            <ListChecks size={16} /> Itinerary
          </button>
          <button type="button" className={mobileView === "map" ? "is-active" : ""} onClick={() => setMobileView("map")}>
            <Map size={16} /> Map
          </button>
        </div>
      )}

      <PlaceDialog
        open={placeDialog.open}
        onClose={() => setPlaceDialog((current) => ({ ...current, open: false }))}
        store={store}
        place={placeDialog.place}
        defaultDayId={placeDialog.dayId}
        saveAsPersonal={placeDialog.personal}
      />
      <ReservationDialog
        open={reservationDialog.open}
        onClose={() => setReservationDialog((current) => ({ ...current, open: false }))}
        store={store}
        reservation={reservationDialog.reservation}
        saveAsPersonal={reservationDialog.personal}
      />
      <OnlyYouPanel open={onlyYouOpen} onClose={() => setOnlyYouOpen(false)} store={store} />
      <TripSettingsDialog open={settingsOpen} onClose={() => setSettingsOpen(false)} store={store} />
      <ConfirmDialog
        open={deleteOpen}
        onClose={() => setDeleteOpen(false)}
        onConfirm={deleteTrip}
        title="Delete this trip?"
        message={`“${trip.title}” and everything in it — days, stops, bookings, costs and invites — will be deleted for everyone. This can't be undone.`}
        confirmLabel="Delete trip"
        destructive
        busy={deleting}
      />
      <PrintSheet store={store} />
    </div>
  );
}

function TripSettingsDialog({ open, onClose, store }: { open: boolean; onClose: () => void; store: ReturnType<typeof useTripStore> }) {
  const trip = store.bundle?.trip;
  const { toast } = useToast();
  const [title, setTitle] = useState(trip?.title ?? "");
  const [destination, setDestination] = useState(trip?.destination ?? "");
  const [startDate, setStartDate] = useState(trip?.start_date ?? "");
  const [endDate, setEndDate] = useState(trip?.end_date ?? "");
  const [currency, setCurrency] = useState(trip?.currency ?? "USD");
  const [timezone, setTimezone] = useState(trip?.timezone ?? estimatedTimezone());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const zones = timezoneOptions();

  useEffect(() => {
    if (!open || !trip) return;
    setTitle(trip.title);
    setDestination(trip.destination ?? "");
    setStartDate(trip.start_date ?? "");
    setEndDate(trip.end_date ?? "");
    setCurrency(trip.currency);
    setTimezone(trip.timezone);
    setError(null);
  }, [open, trip]);

  if (!trip) return null;

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!title.trim()) {
      setError("The trip needs a title.");
      return;
    }
    if (startDate && endDate && endDate < startDate) {
      setError("The end date can't be before the start date.");
      return;
    }
    setSaving(true);
    try {
      await store.updateTrip({
        title: title.trim(),
        destination: destination.trim(),
        start_date: startDate || null,
        end_date: endDate || null,
        currency,
        timezone,
      });
      toast("Trip settings saved", "success");
      onClose();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't save the trip.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Trip settings"
      description="The dates, place and currency at the top of this trip."
      footer={
        <>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={saving}>Cancel</button>
          <button type="submit" form="trip-settings-form" className="button button--primary" disabled={saving || !store.canWrite}>
            {saving ? "Saving…" : "Save settings"}
          </button>
        </>
      }
    >
      <form id="trip-settings-form" className="dialog-form" onSubmit={save}>
        <label className="field">
          <span className="field__label">Trip title</span>
          <input value={title} onChange={(event) => setTitle(event.target.value)} required />
        </label>
        <label className="field">
          <span className="field__label">Destination</span>
          <input value={destination} onChange={(event) => setDestination(event.target.value)} placeholder="Lisbon, Portugal" />
        </label>
        <div className="field-row">
          <label className="field">
            <span className="field__label">Start</span>
            <input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} />
          </label>
          <label className="field">
            <span className="field__label">End</span>
            <input type="date" min={startDate} value={endDate} onChange={(event) => setEndDate(event.target.value)} />
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
            <input list="trip-settings-timezones" value={timezone} onChange={(event) => setTimezone(event.target.value)} />
            <datalist id="trip-settings-timezones">
              {zones.map((zone) => <option value={zone} key={zone} />)}
            </datalist>
          </label>
        </div>
        <p className="field__hint">Changing the dates adds or removes days at the end. Stops keep their day until that day is removed.</p>
        {error && <p className="form-error" role="alert">{error}</p>}
      </form>
    </Dialog>
  );
}

function PrintSheet({ store }: { store: ReturnType<typeof useTripStore> }) {
  const bundle = store.bundle;
  if (!bundle) return null;
  const timezone = bundle.trip.timezone;
  const expensesTotal = bundle.expenses.reduce((sum, expense) => sum + expense.amount, 0);
  const bookingTotal = bundle.reservations.reduce((sum, reservation) => sum + (reservation.cost ?? 0), 0);
  return (
    <section className="print-sheet" aria-hidden="true">
      <header className="print-sheet__header">
        <p>Wanderer · Trip itinerary</p>
        <h1>{bundle.trip.title}</h1>
        <p>{bundle.trip.destination} · {fmtDateRange(bundle.trip.start_date, bundle.trip.end_date)} · {bundle.trip.timezone}</p>
      </header>
      {bundle.days.map((day) => {
        const places = store.places.filter((place) => place.day_id === day.id);
        const bookings = store.reservations.filter((reservation) => reservation.start_at && new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(reservation.start_at)) === day.date);
        return (
          <section className="print-day" key={day.id}>
            <h2>Day {day.day_index + 1} · {fmtDateLong(day.date)}</h2>
            {day.notes && <p className="print-note">{day.notes}</p>}
            {places.map((place, index) => (
              <div className="print-row" key={place.id}>
                <span>{index + 1}</span>
                <div>
                  <strong>{place.name}</strong>
                  {place.address && <small>{place.address}</small>}
                  {place.notes && <small>{place.notes}</small>}
                </div>
                <span>{place.start_time ? new Intl.DateTimeFormat(undefined, { timeZone: timezone, hour: "numeric", minute: "2-digit" }).format(new Date(place.start_time)) : ""}</span>
              </div>
            ))}
            {bookings.map((booking) => (
              <div className="print-row print-row--booking" key={booking.id}>
                <span>★</span>
                <div>
                  <strong>{booking.title}</strong>
                  <small>{booking.provider} {booking.confirmation_code ? `· ${booking.confirmation_code}` : ""}</small>
                </div>
                <span>{booking.start_at ? new Intl.DateTimeFormat(undefined, { timeZone: timezone, hour: "numeric", minute: "2-digit" }).format(new Date(booking.start_at)) : ""}</span>
              </div>
            ))}
            {places.length === 0 && bookings.length === 0 && <p className="print-empty">No stops planned.</p>}
          </section>
        );
      })}
      <footer className="print-sheet__footer">
        <span>{plural(store.places.length, "place")} · {plural(store.reservations.length, "booking")} · {money(expensesTotal + bookingTotal, bundle.trip.currency)} documented cost</span>
        <span>Printed from Wanderer</span>
      </footer>
    </section>
  );
}
