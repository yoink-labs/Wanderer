import { CloudCheck, ListTodo, UserRound } from "lucide-react";
import { dateKeyInZone, fmtDate } from "../lib/dates";
import type { Place, Reservation, TripDay } from "../types";
import type { TripStore } from "./useTripStore";

interface DayRailProps {
  store: TripStore;
  days: TripDay[];
  places: Place[];
  reservations: Reservation[];
  selectedDayId: string | null;
  onSelectDay: (dayId: string | null, options?: { scroll?: boolean }) => void;
  onOpenOnlyYou: () => void;
}

export function DayRail({ store, days, places, reservations, selectedDayId, onSelectDay, onOpenOnlyYou }: DayRailProps) {
  const unscheduled = places.filter((place) => !place.day_id).length;
  const personalCount =
    store.hiddenPlaces.length +
    store.hiddenReservations.length +
    store.privatePlaces.length +
    store.privateReservations.length +
    store.overriddenPlaces.length +
    store.overriddenReservations.length;

  return (
    <aside className="day-rail" aria-label="Trip days">
      <div className="day-rail__head">
        <h2>{days.length ? `${days.length} days` : "No days yet"}</h2>
      </div>

      <nav className="day-rail__list" aria-label="Jump to a day">
        {days.map((day) => {
          const dayPlaces = places.filter((place) => place.day_id === day.id);
          const dayBookings = reservations.filter((reservation) => {
            if (!reservation.start_at || !day.date) return false;
            return dateKeyInZone(reservation.start_at, store.bundle?.trip.timezone ?? "UTC") === day.date;
          });
          const selected = selectedDayId === day.id;
          return (
            <button
              type="button"
              key={day.id}
              className={`day-rail__item ${selected ? "is-selected" : ""}`}
              onClick={() => onSelectDay(day.id, { scroll: true })}
              aria-current={selected ? "true" : undefined}
            >
              <span className="day-rail__marker" aria-hidden="true">
                <span>{day.day_index + 1}</span>
              </span>
              <span className="day-rail__copy">
                <span className="day-rail__title">{day.title || `Day ${day.day_index + 1}`}</span>
                <span className="day-rail__date">{fmtDate(day.date, { weekday: "short", month: "short", day: "numeric" })}</span>
              </span>
              {(dayPlaces.length > 0 || dayBookings.length > 0) && (
                <span className="day-rail__stops">
                  {dayPlaces.length}
                  {dayBookings.length > 0 && <span title={`${dayBookings.length} booking${dayBookings.length === 1 ? "" : "s"}`}>+{dayBookings.length}</span>}
                </span>
              )}
            </button>
          );
        })}
        {unscheduled > 0 && (
          <button
            type="button"
            className={`day-rail__item day-rail__item--ideas ${selectedDayId === "unscheduled" ? "is-selected" : ""}`}
            onClick={() => onSelectDay("unscheduled", { scroll: true })}
          >
            <span className="day-rail__marker day-rail__marker--ideas" aria-hidden="true"><ListTodo size={15} /></span>
            <span className="day-rail__copy">
              <span className="day-rail__title">Ideas</span>
              <span className="day-rail__date">Without a day yet</span>
            </span>
            <span className="day-rail__stops">{unscheduled}</span>
          </button>
        )}
      </nav>

      <div className="day-rail__foot">
        {!store.isGuest && (
          <button type="button" className={`only-you-button ${personalCount ? "has-items" : ""}`} onClick={onOpenOnlyYou}>
            <span className="only-you-button__icon"><UserRound size={15} /></span>
            <span>
              <strong>Only you</strong>
              {personalCount > 0 && <small>{personalCount} private</small>}
            </span>
            {personalCount > 0 && <span className="only-you-button__count">{personalCount}</span>}
          </button>
        )}
        <div className={`saved-chip ${store.offline ? "is-offline" : ""}`}>
          <CloudCheck size={13} aria-hidden="true" />
          <span>{store.offline ? "Offline copy" : "Saved"}</span>
        </div>
      </div>
    </aside>
  );
}
